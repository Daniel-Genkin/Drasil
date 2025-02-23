{-# LANGUAGE PostfixOperators #-}
{-# LANGUAGE Rank2Types #-}
module Language.Drasil.Code.Imperative.Import (
  publicFunc, privateMethod, publicInOutFunc, privateInOutMethod, 
  genConstructor, mkVar, mkVal, convExpr, genCalcBlock, CalcType(..), genModDef,
  genModFuncs, readData, renderC
) where

import Language.Drasil hiding (int, log, ln, exp,
  sin, cos, tan, csc, sec, cot, arcsin, arccos, arctan)
import Database.Drasil (symbResolve)
import Language.Drasil.Code.Imperative.Comments (paramComment, returnComment)
import Language.Drasil.Code.Imperative.ConceptMatch (conceptToGOOL)
import Language.Drasil.Code.Imperative.GenerateGOOL (fApp, genModule, mkParam)
import Language.Drasil.Code.Imperative.Helpers (getUpperBound, liftS, lookupC)
import Language.Drasil.Code.Imperative.Logging (maybeLog, logBody)
import Language.Drasil.Code.Imperative.Parameters (getCalcParams)
import Language.Drasil.Code.Imperative.DrasilState (DrasilState(..))
import Language.Drasil.Chunk.Code (CodeIdea(codeName), codeType, codevar, 
  quantvar, quantfunc)
import Language.Drasil.Chunk.CodeDefinition (CodeDefinition, codeEquat)
import Language.Drasil.Chunk.CodeQuantity (HasCodeType)
import Language.Drasil.Code.CodeQuantityDicts (inFileName, inParams, consts)
import Language.Drasil.CodeSpec (CodeSpec(..), CodeSystInfo(..), Comments(..),
  ConstantRepr(..), ConstantStructure(..), Func(..), FuncData(..), FuncDef(..), 
  FuncStmt(..), Mod(..), Name, Structure(..), asExpr, fstdecl)
import Language.Drasil.Code.DataDesc (DataItem, LinePattern(Repeat, Straight), 
  Data(Line, Lines, JunkData, Singleton), DataDesc, isLine, isLines, getInputs,
  getPatternInputs)

import GOOL.Drasil (Label, ProgramSym, FileSym(..), PermanenceSym(..), 
  BodySym(..), BlockSym(..), TypeSym(..), VariableSym(..), ValueSym(..), 
  NumericExpression(..), BooleanExpression(..), ValueExpression(..), 
  FunctionSym(..), SelectorFunction(..), StatementSym(..), 
  ControlStatementSym(..), ScopeSym(..), ParameterSym(..), MethodSym(..), 
  nonInitConstructor, convType, FS, MS, VS, onStateValue) 
import qualified GOOL.Drasil as C (CodeType(List))

import Prelude hiding (sin, cos, tan, log, exp)
import Data.List ((\\), intersect)
import qualified Data.Map as Map (lookup)
import Data.Maybe (maybe)
import Control.Applicative ((<$>))
import Control.Monad (liftM2,liftM3)
import Control.Monad.Reader (Reader, ask)
import Control.Lens ((^.))

value :: (ProgramSym repr) => UID -> String -> VS (repr (Type repr)) -> 
  Reader DrasilState (VS (repr (Value repr)))
value u s t = do
  g <- ask
  let cs = codeSpec g
      mm = constMap cs
      cm = concMatches g
      maybeInline Inline m = Just m
      maybeInline _ _ = Nothing
  maybe (maybe (do { v <- variable s t; return $ valueOf v }) 
    (convExpr . codeEquat) (Map.lookup u mm >>= maybeInline (conStruct g))) 
    (return . conceptToGOOL) (Map.lookup u cm)

variable :: (ProgramSym repr) => String -> VS (repr (Type repr)) -> 
  Reader DrasilState (VS (repr (Variable repr)))
variable s t = do
  g <- ask
  let cs = csi $ codeSpec g
      defFunc Var = var
      defFunc Const = staticVar
  if s `elem` map codeName (inputs cs) 
    then inputVariable (inStruct g) Var (var s t)
    else if s `elem` map codeName (constants $ csi $ codeSpec g)
      then constVariable (conStruct g) (conRepr g) ((defFunc $ conRepr g) s t)
      else return $ var s t
  
inputVariable :: (ProgramSym repr) => Structure -> ConstantRepr -> 
  VS (repr (Variable repr)) -> Reader DrasilState (VS (repr (Variable repr)))
inputVariable Unbundled _ v = return v
inputVariable Bundled Var v = do
  g <- ask
  let inClsName = "InputParameters"
  ip <- mkVar (codevar inParams)
  return $ if currentClass g == inClsName then objVarSelf v else ip $-> v
inputVariable Bundled Const v = do
  ip <- mkVar (codevar inParams)
  classVariable ip v

constVariable :: (ProgramSym repr) => ConstantStructure -> ConstantRepr -> 
  VS (repr (Variable repr)) -> Reader DrasilState (VS (repr (Variable repr)))
constVariable (Store Bundled) Var v = do
  cs <- mkVar (codevar consts)
  return $ cs $-> v
constVariable (Store Bundled) Const v = do
  cs <- mkVar (codevar consts)
  classVariable cs v
constVariable WithInputs cr v = do
  g <- ask
  inputVariable (inStruct g) cr v
constVariable _ _ v = return v

classVariable :: (ProgramSym repr) => VS (repr (Variable repr)) -> 
  VS (repr (Variable repr)) -> Reader DrasilState (VS (repr (Variable repr)))
classVariable c v = do
  g <- ask
  let checkCurrent m = if currentModule g == m then classVar else extClassVar
  return $ v >>= (\v' -> maybe (error $ "Variable " ++ variableName v' ++ 
    " missing from export map") checkCurrent (Map.lookup (variableName v') 
    (eMap $ codeSpec g)) (onStateValue variableType c) v)

mkVal :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c) => c -> 
  Reader DrasilState (VS (repr (Value repr)))
mkVal v = value (v ^. uid) (codeName v) (convType $ codeType v)

mkVar :: (ProgramSym repr, HasCodeType c, CodeIdea c) => c -> 
  Reader DrasilState (VS (repr (Variable repr)))
mkVar v = variable (codeName v) (convType $ codeType v)

publicFunc :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c) => 
  Label -> VS (repr (Type repr)) -> String -> [c] -> Maybe String -> 
  [MS (repr (Block repr))] -> Reader DrasilState (MS (repr (Method repr)))
publicFunc n t = genMethod (function n public static t) n

privateMethod :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c) => 
  Label -> VS (repr (Type repr)) -> String -> [c] -> Maybe String -> 
  [MS (repr (Block repr))] -> Reader DrasilState (MS (repr (Method repr)))
privateMethod n t = genMethod (method n private dynamic t) n

publicInOutFunc :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c, Eq c) 
  => Label -> String -> [c] -> [c] -> [MS (repr (Block repr))] -> 
  Reader DrasilState (MS (repr (Method repr)))
publicInOutFunc n = genInOutFunc (inOutFunc n) (docInOutFunc n) public static n

privateInOutMethod :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c,
  Eq c) => Label -> String -> [c] -> [c] -> [MS (repr (Block repr))] 
  -> Reader DrasilState (MS (repr (Method repr)))
privateInOutMethod n = genInOutFunc (inOutMethod n) (docInOutMethod n) 
  private dynamic n

genConstructor :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c) => 
  Label -> String -> [c] -> [MS (repr (Block repr))] -> 
  Reader DrasilState (MS (repr (Method repr)))
genConstructor n desc p = genMethod nonInitConstructor n desc p Nothing

genMethod :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c) => 
  ([MS (repr (Parameter repr))] -> MS (repr (Body repr)) -> 
  MS (repr (Method repr))) -> Label -> String -> [c] -> Maybe String -> 
  [MS (repr (Block repr))] -> Reader DrasilState (MS (repr (Method repr)))
genMethod f n desc p r b = do
  g <- ask
  vars <- mapM mkVar p
  bod <- logBody n vars b
  let ps = map mkParam vars
      fn = f ps bod
  pComms <- mapM (paramComment . (^. uid)) p
  return $ if CommentFunc `elem` commented g
    then docFunc desc pComms r fn else fn

genInOutFunc :: (ProgramSym repr, HasUID c, HasCodeType c, CodeIdea c, Eq c) => 
  (repr (Scope repr) -> repr (Permanence repr) -> [VS (repr (Variable repr))] 
    -> [VS (repr (Variable repr))] -> [VS (repr (Variable repr))] -> 
    MS (repr (Body repr)) -> MS (repr (Method repr))) -> 
  (repr (Scope repr) -> repr (Permanence repr) -> String -> 
    [(String, VS (repr (Variable repr)))] -> 
    [(String, VS (repr (Variable repr)))] -> 
    [(String, VS (repr (Variable repr)))] -> MS (repr (Body repr)) -> 
    MS (repr (Method repr))) -> 
  repr (Scope repr) -> repr (Permanence repr) -> Label -> String -> [c] -> 
  [c] -> [MS (repr (Block repr))] -> 
  Reader DrasilState (MS (repr (Method repr)))
genInOutFunc f docf s pr n desc ins' outs' b = do
  g <- ask
  let ins = ins' \\ outs'
      outs = outs' \\ ins'
      both = ins' `intersect` outs'
  inVs <- mapM mkVar ins
  outVs <- mapM mkVar outs
  bothVs <- mapM mkVar both
  bod <- logBody n (bothVs ++ inVs) b
  pComms <- mapM (paramComment . (^. uid)) ins
  oComms <- mapM (paramComment . (^. uid)) outs
  bComms <- mapM (paramComment . (^. uid)) both
  return $ if CommentFunc `elem` commented g 
    then docf s pr desc (zip pComms inVs) (zip oComms outVs) (zip 
    bComms bothVs) bod else f s pr inVs outVs bothVs bod

convExpr :: (ProgramSym repr) => Expr -> Reader DrasilState (VS (repr (Value repr)))
convExpr (Dbl d) = return $ litFloat d
convExpr (Int i) = return $ litInt i
convExpr (Str s) = return $ litString s
convExpr (Perc a b) = return $ litFloat $ fromIntegral a / (10 ** fromIntegral b)
convExpr (AssocA Add l) = foldl1 (#+)  <$> mapM convExpr l
convExpr (AssocA Mul l) = foldl1 (#*)  <$> mapM convExpr l
convExpr (AssocB And l) = foldl1 (?&&) <$> mapM convExpr l
convExpr (AssocB Or l)  = foldl1 (?||) <$> mapM convExpr l
convExpr Deriv{} = return $ litString "**convExpr :: Deriv unimplemented**"
convExpr (C c)   = do
  g <- ask
  let v = quantvar (lookupC g c)
  mkVal v
convExpr (FCall (C c) x) = do
  g <- ask
  let info = sysinfodb $ csi $ codeSpec g
      mem = eMap $ codeSpec g
      funcCd = quantfunc (symbResolve info c)
      funcNm = codeName funcCd
      funcTp = convType $ codeType funcCd
  args <- mapM convExpr x
  maybe (error $ "Call to non-existent function" ++ funcNm) 
    (\f -> fApp f funcNm funcTp args) (Map.lookup funcNm mem)
convExpr FCall{}   = return $ litString "**convExpr :: FCall unimplemented**"
convExpr (UnaryOp o u) = fmap (unop o) (convExpr u)
convExpr (BinaryOp Frac (Int a) (Int b)) =
  return $ litFloat (fromIntegral a) #/ litFloat (fromIntegral b) -- hack to deal with integer division
convExpr (BinaryOp o a b)  = liftM2 (bfunc o) (convExpr a) (convExpr b)
convExpr (Case c l)      = doit l -- FIXME this is sub-optimal
  where
    doit [] = error "should never happen"
    doit [(e,_)] = convExpr e -- should always be the else clause
    doit ((e,cond):xs) = liftM3 inlineIf (convExpr cond) (convExpr e) 
      (convExpr (Case c xs))
convExpr Matrix{}    = error "convExpr: Matrix"
convExpr Operator{} = error "convExpr: Operator"
convExpr IsIn{}    = error "convExpr: IsIn"
convExpr (RealI c ri)  = do
  g <- ask
  convExpr $ renderRealInt (lookupC g c) ri

renderC :: (HasUID c, HasSymbol c) => c -> Constraint -> Expr
renderC s (Range _ rr)          = renderRealInt s rr
renderC s (EnumeratedReal _ rr) = IsIn (sy s) (DiscreteD rr)
renderC s (EnumeratedStr _ rr)  = IsIn (sy s) (DiscreteS rr)

renderRealInt :: (HasUID c, HasSymbol c) => c -> RealInterval Expr Expr -> Expr
renderRealInt s (Bounded (Inc,a) (Inc,b)) = (a $<= sy s) $&& (sy s $<= b)
renderRealInt s (Bounded (Inc,a) (Exc,b)) = (a $<= sy s) $&& (sy s $<  b)
renderRealInt s (Bounded (Exc,a) (Inc,b)) = (a $<  sy s) $&& (sy s $<= b)
renderRealInt s (Bounded (Exc,a) (Exc,b)) = (a $<  sy s) $&& (sy s $<  b)
renderRealInt s (UpTo (Inc,a))    = sy s $<= a
renderRealInt s (UpTo (Exc,a))    = sy s $< a
renderRealInt s (UpFrom (Inc,a))  = sy s $>= a
renderRealInt s (UpFrom (Exc,a))  = sy s $>  a

unop :: (ProgramSym repr) => UFunc -> (VS (repr (Value repr)) -> 
  VS (repr (Value repr)))
unop Sqrt = (#/^)
unop Log  = log
unop Ln   = ln
unop Abs  = (#|)
unop Exp  = exp
unop Sin  = sin
unop Cos  = cos
unop Tan  = tan
unop Csc  = csc
unop Sec  = sec
unop Cot  = cot
unop Arcsin = arcsin
unop Arccos = arccos
unop Arctan = arctan
unop Dim  = listSize
unop Norm = error "unop: Norm not implemented"
unop Not  = (?!)
unop Neg  = (#~)

bfunc :: (ProgramSym repr) => BinOp -> (VS (repr (Value repr)) -> 
  VS (repr (Value repr)) -> VS (repr (Value repr)))
bfunc Eq    = (?==)
bfunc NEq   = (?!=)
bfunc Gt    = (?>)
bfunc Lt    = (?<)
bfunc LEq   = (?<=)
bfunc GEq   = (?>=)
bfunc Cross = error "bfunc: Cross not implemented"
bfunc Pow   = (#^)
bfunc Subt  = (#-)
bfunc Impl  = error "convExpr :=>"
bfunc Iff   = error "convExpr :<=>"
bfunc Dot   = error "convExpr DotProduct"
bfunc Frac  = (#/)
bfunc Index = listAccess

------- CALC ----------

genCalcFunc :: (ProgramSym repr) => CodeDefinition -> 
  Reader DrasilState (MS (repr (Method repr)))
genCalcFunc cdef = do
  parms <- getCalcParams cdef
  let nm = codeName cdef
      tp = convType $ codeType cdef
  blck <- genCalcBlock CalcReturn cdef (codeEquat cdef)
  desc <- returnComment $ cdef ^. uid
  publicFunc
    nm
    tp
    ("Calculates " ++ desc)
    parms
    (Just desc)
    [blck]

data CalcType = CalcAssign | CalcReturn deriving Eq

genCalcBlock :: (ProgramSym repr) => CalcType -> CodeDefinition -> Expr ->
  Reader DrasilState (MS (repr (Block repr)))
genCalcBlock t v (Case c e) = genCaseBlock t v c e
genCalcBlock t v e
    | t == CalcAssign  = fmap block $ liftS $ do { vv <- mkVar v; ee <-
      convExpr e; l <- maybeLog vv; return $ multi $ assign vv ee : l}
    | otherwise        = block <$> liftS (returnState <$> convExpr e)

genCaseBlock :: (ProgramSym repr) => CalcType -> CodeDefinition -> Completeness 
  -> [(Expr,Relation)] -> Reader DrasilState (MS (repr (Block repr)))
genCaseBlock _ _ _ [] = error $ "Case expression with no cases encountered" ++
  " in code generator"
genCaseBlock t v c cs = do
  ifs <- mapM (\(e,r) -> liftM2 (,) (convExpr r) (calcBody e)) (ifEs c)
  els <- elseE c
  return $ block [ifCond ifs els]
  where calcBody e = fmap body $ liftS $ genCalcBlock t v e
        ifEs Complete = init cs
        ifEs Incomplete = cs
        elseE Complete = calcBody $ fst $ last cs
        elseE Incomplete = return $ oneLiner $ throw $  
          "Undefined case encountered in function " ++ codeName v

-- medium hacks --
genModDef :: (ProgramSym repr) => Mod -> 
  Reader DrasilState (FS (repr (RenderFile repr)))
genModDef (Mod n desc fs) = genModule n desc (map (fmap Just . genFunc) fs) []

genModFuncs :: (ProgramSym repr) => Mod -> 
  [Reader DrasilState (MS (repr (Method repr)))]
genModFuncs (Mod _ _ fs) = map genFunc fs

genFunc :: (ProgramSym repr) => Func -> Reader DrasilState (MS (repr (Method repr)))
genFunc (FDef (FuncDef n desc parms o rd s)) = do
  g <- ask
  stmts <- mapM convStmt s
  vars <- mapM mkVar (fstdecl (sysinfodb $ csi $ codeSpec g) s \\ parms)
  publicFunc n (convType o) desc parms rd [block $ map varDec vars ++ stmts]
genFunc (FData (FuncData n desc ddef)) = genDataFunc n desc ddef
genFunc (FCD cd) = genCalcFunc cd

convStmt :: (ProgramSym repr) => FuncStmt -> Reader DrasilState (MS (repr (Statement repr)))
convStmt (FAsg v e) = do
  e' <- convExpr e
  v' <- mkVar v
  l <- maybeLog v'
  return $ multi $ assign v' e' : l
convStmt (FFor v e st) = do
  stmts <- mapM convStmt st
  vari <- mkVar v
  e' <- convExpr $ getUpperBound e
  return $ forRange vari (litInt 0) e' (litInt 1) (bodyStatements stmts)
convStmt (FWhile e st) = do
  stmts <- mapM convStmt st
  e' <- convExpr e
  return $ while e' (bodyStatements stmts)
convStmt (FCond e tSt []) = do
  stmts <- mapM convStmt tSt
  e' <- convExpr e
  return $ ifNoElse [(e', bodyStatements stmts)]
convStmt (FCond e tSt eSt) = do
  stmt1 <- mapM convStmt tSt
  stmt2 <- mapM convStmt eSt
  e' <- convExpr e
  return $ ifCond [(e', bodyStatements stmt1)] (bodyStatements stmt2)
convStmt (FRet e) = do
  e' <- convExpr e
  return $ returnState e'
convStmt (FThrow s) = return $ throw s
convStmt (FTry t c) = do
  stmt1 <- mapM convStmt t
  stmt2 <- mapM convStmt c
  return $ tryCatch (bodyStatements stmt1) (bodyStatements stmt2)
convStmt FContinue = return continue
convStmt (FDec v) = do
  vari <- mkVar v
  let convDec (C.List _) = listDec 0 vari
      convDec _ = varDec vari
  return $ convDec (codeType v) 
convStmt (FProcCall n l) = do
  e' <- convExpr (FCall (asExpr n) l)
  return $ valState e'
convStmt (FAppend a b) = do
  a' <- convExpr a
  b' <- convExpr b
  return $ valState $ listAppend a' b'

genDataFunc :: (ProgramSym repr) => Name -> String -> DataDesc -> 
  Reader DrasilState (MS (repr (Method repr)))
genDataFunc nameTitle desc ddef = do
  let parms = getInputs ddef
  bod <- readData ddef
  publicFunc nameTitle void desc (codevar inFileName : parms) Nothing bod

-- this is really ugly!!
readData :: (ProgramSym repr) => DataDesc -> Reader DrasilState
  [MS (repr (Block repr))]
readData ddef = do
  inD <- mapM inData ddef
  v_filename <- mkVal $ codevar inFileName
  return [block $ 
    varDec var_infile :
    (if any (\d -> isLine d || isLines d) ddef then [varDec var_line, listDec 0 var_linetokens] else []) ++
    [listDec 0 var_lines | any isLines ddef] ++
    openFileR var_infile v_filename :
    concat inD ++ [
    closeFile v_infile ]]
  where inData :: (ProgramSym repr) => Data -> Reader DrasilState [MS (repr (Statement repr))]
        inData (Singleton v) = do
            vv <- mkVar v
            l <- maybeLog vv
            return [multi $ getFileInput v_infile vv : l]
        inData JunkData = return [discardFileLine v_infile]
        inData (Line lp d) = do
          lnI <- lineData Nothing lp
          logs <- getEntryVarLogs lp
          return $ [getFileInputLine v_infile var_line, 
            stringSplit d var_linetokens v_line] ++ lnI ++ logs
        inData (Lines lp ls d) = do
          lnV <- lineData (Just "_temp") lp
          logs <- getEntryVarLogs lp
          let readLines Nothing = [getFileInputAll v_infile var_lines,
                forRange var_i (litInt 0) (listSize v_lines) (litInt 1)
                  (bodyStatements $ stringSplit d var_linetokens (
                  listAccess v_lines v_i) : lnV)]
              readLines (Just numLines) = [forRange var_i (litInt 0) 
                (litInt numLines) (litInt 1)
                (bodyStatements $
                  [getFileInputLine v_infile var_line,
                   stringSplit d var_linetokens v_line
                  ] ++ lnV)]
          return $ readLines ls ++ logs
        ---------------
        lineData :: (ProgramSym repr) => Maybe String -> LinePattern -> 
          Reader DrasilState [MS (repr (Statement repr))]
        lineData s p@(Straight _) = do
          vs <- getEntryVars s p
          return [stringListVals vs v_linetokens]
        lineData s p@(Repeat ds) = do
          vs <- getEntryVars s p
          return $ clearTemps s ds ++ stringListLists vs v_linetokens 
            : appendTemps s ds
        ---------------
        clearTemps :: (ProgramSym repr) => Maybe String -> [DataItem] -> 
          [MS (repr (Statement repr))]
        clearTemps Nothing _ = []
        clearTemps (Just sfx) es = map (clearTemp sfx) es
        ---------------
        clearTemp :: (ProgramSym repr) => String -> DataItem -> 
          MS (repr (Statement repr))
        clearTemp sfx v = listDecDef (var (codeName v ++ sfx) 
          (listInnerType $ convType $ codeType v)) []
        ---------------
        appendTemps :: (ProgramSym repr) => Maybe String -> [DataItem] -> 
          [MS (repr (Statement repr))]
        appendTemps Nothing _ = []
        appendTemps (Just sfx) es = map (appendTemp sfx) es
        ---------------
        appendTemp :: (ProgramSym repr) => String -> DataItem -> 
          MS (repr (Statement repr))
        appendTemp sfx v = valState $ listAppend 
          (valueOf $ var (codeName v) (convType $ codeType v)) 
          (valueOf $ var (codeName v ++ sfx) (convType $ codeType v))
        ---------------
        l_line, l_lines, l_linetokens, l_infile, l_i :: Label
        var_line, var_lines, var_linetokens, var_infile, var_i :: 
          (ProgramSym repr) => VS (repr (Variable repr))
        v_line, v_lines, v_linetokens, v_infile, v_i ::
          (ProgramSym repr) => VS (repr (Value repr))
        l_line = "line"
        var_line = var l_line string
        v_line = valueOf var_line
        l_lines = "lines"
        var_lines = var l_lines (listType string)
        v_lines = valueOf var_lines
        l_linetokens = "linetokens"
        var_linetokens = var l_linetokens (listType string)
        v_linetokens = valueOf var_linetokens
        l_infile = "infile"
        var_infile = var l_infile infile
        v_infile = valueOf var_infile
        l_i = "i"
        var_i = var l_i int
        v_i = valueOf var_i

getEntryVars :: (ProgramSym repr) => Maybe String -> LinePattern -> 
  Reader DrasilState [VS (repr (Variable repr))]
getEntryVars s lp = mapM (maybe mkVar (\st v -> variable (codeName v ++ st) 
  (listInnerType $ convType $ codeType v)) s) (getPatternInputs lp)

getEntryVarLogs :: (ProgramSym repr) => LinePattern -> 
  Reader DrasilState [MS (repr (Statement repr))]
getEntryVarLogs lp = do
  vs <- getEntryVars Nothing lp
  logs <- mapM maybeLog vs
  return $ concat logs
