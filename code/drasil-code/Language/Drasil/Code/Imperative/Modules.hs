module Language.Drasil.Code.Imperative.Modules (
  genMain, genMainFunc, chooseInModule, genInputClass, genInputDerived, 
  genInputConstraints, genInputFormat, genConstMod, genConstClass, genOutputMod,
  genOutputFormat, genSampleInput
) where

import Language.Drasil
import Database.Drasil (ChunkDB)
import Language.Drasil.Code.Imperative.Descriptions (constClassDesc, 
  constModDesc, derivedValuesDesc, dvFuncDesc, inConsFuncDesc, inFmtFuncDesc, 
  inputClassDesc, inputConstraintsDesc, inputConstructorDesc, inputFormatDesc, 
  inputParametersDesc, modDesc, outputFormatDesc, woFuncDesc)
import Language.Drasil.Code.Imperative.FunctionCalls (getCalcCall,
  getAllInputCalls, getOutputCall)
import Language.Drasil.Code.Imperative.GenerateGOOL (genModule, publicClass, 
  privateClass)
import Language.Drasil.Code.Imperative.Helpers (liftS)
import Language.Drasil.Code.Imperative.Import (CalcType(CalcAssign), convExpr,
  genCalcBlock, genConstructor, mkVal, mkVar, privateInOutMethod, privateMethod,
  publicFunc, publicInOutFunc, readData, renderC)
import Language.Drasil.Code.Imperative.Logging (maybeLog, varLogFile)
import Language.Drasil.Code.Imperative.Parameters (getConstraintParams, 
  getDerivedIns, getDerivedOuts, getInConstructorParams, getInputFormatIns, 
  getInputFormatOuts, getOutputParams)
import Language.Drasil.Code.Imperative.DrasilState (DrasilState(..), inMod)
import Language.Drasil.Code.Imperative.GOOL.Symantics (AuxiliarySym(..))
import Language.Drasil.Chunk.Code (CodeIdea(codeName, codeChunk), CodeChunk, 
  codeType, codevar, physLookup, sfwrLookup)
import Language.Drasil.Chunk.CodeDefinition (CodeDefinition, codeEquat)
import Language.Drasil.Chunk.CodeQuantity (HasCodeType)
import Language.Drasil.Code.CodeQuantityDicts (inFileName, inParams, consts)
import Language.Drasil.Code.DataDesc (DataDesc, junkLine, singleton)
import Language.Drasil.CodeSpec (AuxFile(..), CodeSpec(..), CodeSystInfo(..),
  Comments(CommentFunc), ConstantStructure(..), ConstantRepr(..), 
  ConstraintBehaviour(..), InputModule(..), Logging(..))
import Language.Drasil.Printers (Linearity(Linear), exprDoc)

import GOOL.Drasil (ProgramSym, FileSym(..), BodySym(..), BlockSym(..), 
  PermanenceSym(..), TypeSym(..), VariableSym(..), ValueSym(..), 
  BooleanExpression(..), StatementSym(..), ControlStatementSym(..), 
  ScopeSym(..), MethodSym(..), StateVarSym(..), ClassSym(..), ScopeTag(..), 
  convType, FS, CS, MS, VS)

import Prelude hiding (print)
import Data.List (intersperse, intercalate, partition)
import Data.Map ((!), member)
import qualified Data.Map as Map (lookup, filter)
import Data.Maybe (maybeToList, catMaybes)
import Control.Applicative ((<$>))
import Control.Monad.Reader (Reader, ask, asks, withReader)
import Control.Lens ((^.))
import Text.PrettyPrint.HughesPJ (render)

---- MAIN ---

genMain :: (ProgramSym repr) => Reader DrasilState (FS (repr (RenderFile repr)))
genMain = genModule "Control" "Controls the flow of the program" 
  [fmap Just genMainFunc] []

genMainFunc :: (ProgramSym repr) => Reader DrasilState (MS (repr (Method repr)))
genMainFunc = do
    g <- ask
    v_filename <- mkVar $ codevar inFileName
    logInFile <- maybeLog v_filename
    ip <- getInputDecl
    co <- initConsts
    ics <- getAllInputCalls
    varDef <- mapM getCalcCall (execOrder $ csi $ codeSpec g)
    wo <- getOutputCall
    return $ (if CommentFunc `elem` commented g then docMain else mainFunction)
      $ bodyStatements $
      initLogFileVar (logKind g) ++
      varDecDef v_filename (arg 0) : logInFile ++
      catMaybes [ip, co] ++ ics ++ catMaybes (varDef ++ [wo])

getInputDecl :: (ProgramSym repr) => Reader DrasilState 
  (Maybe (MS (repr (Statement repr))))
getInputDecl = do
  g <- ask
  v_params <- mkVar (codevar inParams)
  constrParams <- getInConstructorParams 
  cps <- mapM mkVal constrParams
  let cname = "InputParameters"
      getDecl ([],[]) = constIns (partition (flip member (eMap $ codeSpec g) . 
        codeName) (map codeChunk $ constants $ csi $ codeSpec g)) (conRepr g) 
        (conStruct g)
      getDecl ([],ins) = do
        vars <- mapM mkVar ins
        return $ Just $ multi $ map varDec vars
      getDecl (i:_,[]) = return $ Just $ (if currentModule g == 
        eMap (codeSpec g) ! codeName i then objDecNew 
        else extObjDecNew cname) v_params cps
      getDecl _ = error ("Inputs or constants are only partially contained in " 
        ++ "a class")
      constIns ([],[]) _ _ = return Nothing
      -- If Const is chosen, don't declare an object because constants are static and accessed through class
      constIns cs Var WithInputs = getDecl cs
      constIns _ _ _ = return Nothing 
  getDecl (partition (flip member (eMap $ codeSpec g) . codeName) 
    (inputs $ csi $ codeSpec g))

initConsts :: (ProgramSym repr) => Reader DrasilState 
  (Maybe (MS (repr (Statement repr))))
initConsts = do
  g <- ask
  v_consts <- mkVar (codevar consts)
  let cname = "Constants"
      getDecl _ Inline = return Nothing
      getDecl ([],[]) _ = return Nothing
      getDecl (_,[]) WithInputs = return Nothing
      getDecl (c:_,[]) _ = asks (constCont c . conRepr)
      getDecl ([],cs) _ = do 
        vars <- mapM mkVar cs
        vals <- mapM (convExpr . codeEquat) cs
        logs <- mapM maybeLog vars
        return $ Just $ multi $ zipWith (defFunc $ conRepr g) vars vals ++ 
          concat logs
      getDecl _ _ = error "Only some constants present in export map"
      constCont c Var = Just $ (if currentModule g == eMap (codeSpec g) ! 
        codeName c then objDecNewNoParams else extObjDecNewNoParams cname) 
        v_consts
      constCont _ Const = Nothing
      defFunc Var = varDecDef
      defFunc Const = constDecDef
  getDecl (partition (flip member (eMap $ codeSpec g) . codeName) 
    (constants $ csi $ codeSpec g)) (conStruct g)

initLogFileVar :: (ProgramSym repr) => Logging -> [MS (repr (Statement repr))]
initLogFileVar LogVar = [varDec varLogFile]
initLogFileVar LogAll = [varDec varLogFile]
initLogFileVar _ = []

------- INPUT ----------

chooseInModule :: (ProgramSym repr) => InputModule -> Reader DrasilState 
  [FS (repr (RenderFile repr))]
chooseInModule Combined = genInputModCombined
chooseInModule Separated = genInputModSeparated

genInputModSeparated :: (ProgramSym repr) => 
  Reader DrasilState [FS (repr (RenderFile repr))]
genInputModSeparated = do
  ipDesc <- modDesc inputParametersDesc
  ifDesc <- modDesc (liftS inputFormatDesc)
  dvDesc <- modDesc (liftS derivedValuesDesc)
  icDesc <- modDesc (liftS inputConstraintsDesc)
  sequence 
    [genModule "InputParameters" ipDesc [] [genInputClass Pub],
    genModule "InputFormat" ifDesc [genInputFormat Pub] [],
    genModule "DerivedValues" dvDesc [genInputDerived Pub] [],
    genModule "InputConstraints" icDesc [genInputConstraints Pub] []]

genInputModCombined :: (ProgramSym repr) => 
  Reader DrasilState [FS (repr (RenderFile repr))]
genInputModCombined = do
  ipDesc <- modDesc inputParametersDesc
  let cname = "InputParameters"
      genMod :: (ProgramSym repr) => Maybe (CS (repr (Class repr))) ->
        Reader DrasilState (FS (repr (RenderFile repr)))
      genMod Nothing = genModule cname ipDesc [genInputFormat Pub, 
        genInputDerived Pub, genInputConstraints Pub] []
      genMod _ = genModule cname ipDesc [] [genInputClass Pub]
  ic <- genInputClass Pub
  liftS $ genMod ic

constVarFunc :: (ProgramSym repr) => ConstantRepr -> String ->
  (VS (repr (Variable repr)) -> VS (repr (Value repr)) -> 
  CS (repr (StateVar repr)))
constVarFunc Var n = stateVarDef n public dynamic
constVarFunc Const n = constVar n public

genInputClass :: (ProgramSym repr) => ScopeTag -> 
  Reader DrasilState (Maybe (CS (repr (Class repr))))
genInputClass scp = withReader (\s -> s {currentClass = cname}) $ do
  g <- ask
  let ins = inputs $ csi $ codeSpec g
      cs = constants $ csi $ codeSpec g
      filt :: (CodeIdea c) => [c] -> [c]
      filt = filter (flip member (eMap $ codeSpec g) . codeName)
      includedConstants :: (CodeIdea c) => ConstantStructure -> [c] -> [c]
      includedConstants WithInputs cs' = filt cs'
      includedConstants _ _ = []
      methods :: (ProgramSym repr) => InputModule -> 
        Reader DrasilState [MS (repr (Method repr))]
      methods Separated = return []
      methods Combined = concat <$> mapM (fmap maybeToList) 
        [genInputConstructor, genInputFormat Priv, 
        genInputDerived Priv, genInputConstraints Priv]
      genClass :: (ProgramSym repr) => [CodeChunk] -> [CodeDefinition] -> 
        Reader DrasilState (Maybe (CS (repr (Class repr))))
      genClass [] [] = return Nothing
      genClass inps csts = do
        vals <- mapM (convExpr . codeEquat) csts
        let getFunc Pub = publicClass
            getFunc Priv = privateClass
            f = getFunc scp
            inputVars = map (\x -> pubMVar (var (codeName x) (convType $ 
              codeType x))) inps
            constVars = zipWith (\c vl -> constVarFunc (conRepr g) cname
              (var (codeName c) (convType $ codeType c)) vl) csts vals
        icDesc <- inputClassDesc
        c <- f icDesc cname Nothing (inputVars ++ constVars) (methods $ inMod g)
        return $ Just c
  genClass (filt ins) (includedConstants (conStruct g) cs)
  where cname = "InputParameters"

genInputConstructor :: (ProgramSym repr) => Reader DrasilState 
  (Maybe (MS (repr (Method repr))))
genInputConstructor = do
  g <- ask
  let dl = defList $ codeSpec g
      genCtor False = return Nothing
      genCtor True = do 
        cdesc <- inputConstructorDesc
        cparams <- getInConstructorParams    
        ics <- getAllInputCalls
        ctor <- genConstructor "InputParameters" cdesc cparams [block ics]
        return $ Just ctor
  genCtor $ any (`elem` dl) ["get_input", "derived_values", 
    "input_constraints"]

genInputDerived :: (ProgramSym repr) => ScopeTag -> 
  Reader DrasilState (Maybe (MS (repr (Method repr))))
genInputDerived s = do
  g <- ask
  let dvals = derivedInputs $ csi $ codeSpec g
      getFunc Pub = publicInOutFunc
      getFunc Priv = privateInOutMethod
      genDerived :: (ProgramSym repr) => Bool -> Reader DrasilState 
        (Maybe (MS (repr (Method repr))))
      genDerived False = return Nothing
      genDerived _ = do
        ins <- getDerivedIns
        outs <- getDerivedOuts
        bod <- mapM (\x -> genCalcBlock CalcAssign x (codeEquat x)) dvals
        desc <- dvFuncDesc
        mthd <- getFunc s "derived_values" desc ins outs bod
        return $ Just mthd
  genDerived $ "derived_values" `elem` defList (codeSpec g)

genInputConstraints :: (ProgramSym repr) => ScopeTag ->
  Reader DrasilState (Maybe (MS (repr (Method repr))))
genInputConstraints s = do
  g <- ask
  let cm = cMap $ csi $ codeSpec g
      getFunc Pub = publicFunc
      getFunc Priv = privateMethod
      genConstraints :: (ProgramSym repr) => Bool -> Reader DrasilState 
        (Maybe (MS (repr (Method repr))))
      genConstraints False = return Nothing
      genConstraints _ = do
        h <- ask
        parms <- getConstraintParams
        let varsList = filter (\i -> member (i ^. uid) cm) (inputs $ csi $ 
              codeSpec h)
            sfwrCs   = map (sfwrLookup cm) varsList
            physCs   = map (physLookup cm) varsList
        sf <- sfwrCBody sfwrCs
        hw <- physCBody physCs
        desc <- inConsFuncDesc
        mthd <- getFunc s "input_constraints" void desc parms 
          Nothing [block sf, block hw]
        return $ Just mthd
  genConstraints $ "input_constraints" `elem` defList (codeSpec g)

sfwrCBody :: (HasUID q, HasSymbol q, CodeIdea q, HasCodeType q, ProgramSym repr) 
  => [(q,[Constraint])] -> Reader DrasilState [MS (repr (Statement repr))]
sfwrCBody cs = do
  g <- ask
  let cb = onSfwrC g
  chooseConstr cb cs

physCBody :: (HasUID q, HasSymbol q, CodeIdea q, HasCodeType q, ProgramSym repr) 
  => [(q,[Constraint])] -> Reader DrasilState [MS (repr (Statement repr))]
physCBody cs = do
  g <- ask
  let cb = onPhysC g
  chooseConstr cb cs

chooseConstr :: (HasUID q, HasSymbol q, CodeIdea q, HasCodeType q, 
  ProgramSym repr) => ConstraintBehaviour -> [(q,[Constraint])] -> 
  Reader DrasilState [MS (repr (Statement repr))]
chooseConstr Warning   cs = do
  checks <- mapM constrWarn cs
  return $ concat checks
chooseConstr Exception cs = do
  checks <- mapM constrExc cs
  return $ concat checks

constrWarn :: (HasUID q, HasSymbol q, CodeIdea q, HasCodeType q, ProgramSym repr)
  => (q,[Constraint]) -> Reader DrasilState [MS (repr (Statement repr))]
constrWarn c = do
  let q = fst c
      cs = snd c
  conds <- mapM (convExpr . renderC q) cs
  msgs <- mapM (constraintViolatedMsg q "suggested") cs
  return $ zipWith (\cond m -> ifNoElse [((?!) cond, bodyStatements $
    printStr "Warning: " : m)]) conds msgs

constrExc :: (HasUID q, HasSymbol q, CodeIdea q, HasCodeType q, ProgramSym repr) 
  => (q,[Constraint]) -> Reader DrasilState [MS (repr (Statement repr))]
constrExc c = do
  let q = fst c
      cs = snd c
  conds <- mapM (convExpr . renderC q) cs
  msgs <- mapM (constraintViolatedMsg q "expected") cs
  return $ zipWith (\cond m -> ifNoElse [((?!) cond, bodyStatements $ 
    m ++ [throw "InputError"])]) conds msgs

constraintViolatedMsg :: (CodeIdea q, HasUID q, HasCodeType q, ProgramSym repr) 
  => q -> String -> Constraint -> Reader DrasilState 
  [MS (repr (Statement repr))]
constraintViolatedMsg q s c = do
  pc <- printConstraint c 
  v <- mkVal q
  return $ [printStr $ codeName q ++ " has value ",
    print v,
    printStr $ " but " ++ s ++ " to be "] ++ pc

printConstraint :: (ProgramSym repr) => Constraint -> 
  Reader DrasilState [MS (repr (Statement repr))]
printConstraint c = do
  g <- ask
  let db = sysinfodb $ csi $ codeSpec g
      printConstraint' :: (ProgramSym repr) => Constraint -> Reader DrasilState 
        [MS (repr (Statement repr))]
      printConstraint' (Range _ (Bounded (_,e1) (_,e2))) = do
        lb <- convExpr e1
        ub <- convExpr e2
        return $ [printStr "between ",
          print lb] ++ printExpr e1 db ++
          [printStr " and ", print ub] ++ printExpr e2 db ++ [printStrLn "."]
      printConstraint' (Range _ (UpTo (_,e))) = do
        ub <- convExpr e
        return $ [printStr "below ",
          print ub] ++ printExpr e db ++ [printStrLn "."]
      printConstraint' (Range _ (UpFrom (_,e))) = do
        lb <- convExpr e
        return $ [printStr "above ",
          print lb] ++ printExpr e db ++ [printStrLn "."]
      printConstraint' (EnumeratedReal _ ds) = return [
        printStrLn $ "one of: " ++ intercalate ", " (map show ds)]
      printConstraint' (EnumeratedStr _ ss) = return [
        printStrLn $ "one of: " ++ intercalate ", " ss]
  printConstraint' c

printExpr :: (ProgramSym repr) => Expr -> ChunkDB -> [MS (repr (Statement repr))]
printExpr (Dbl _) _ = []
printExpr (Int _) _ = []
printExpr e db = [printStr $ " (" ++ render (exprDoc db Implementation Linear e)
  ++ ")"]

genInputFormat :: (ProgramSym repr) => ScopeTag -> 
  Reader DrasilState (Maybe (MS (repr (Method repr))))
genInputFormat s = do
  g <- ask
  dd <- genDataDesc
  let getFunc Pub = publicInOutFunc
      getFunc Priv = privateInOutMethod
      genInFormat :: (ProgramSym repr) => Bool -> Reader DrasilState 
        (Maybe (MS (repr (Method repr))))
      genInFormat False = return Nothing
      genInFormat _ = do
        ins <- getInputFormatIns
        outs <- getInputFormatOuts
        bod <- readData dd
        desc <- inFmtFuncDesc
        mthd <- getFunc s "get_input" desc ins outs bod
        return $ Just mthd
  genInFormat $ "get_input" `elem` defList (codeSpec g)

genDataDesc :: Reader DrasilState DataDesc
genDataDesc = do
  g <- ask
  return $ junkLine : 
    intersperse junkLine (map singleton (extInputs $ csi $ codeSpec g))

genSampleInput :: (AuxiliarySym repr) => Reader DrasilState [repr (Auxiliary repr)]
genSampleInput = do
  g <- ask
  dd <- genDataDesc
  return [sampleInput (sysinfodb $ csi $ codeSpec g) dd (sampleData g) | SampleInput `elem` 
    auxiliaries g]

----- CONSTANTS -----

genConstMod :: (ProgramSym repr) => Reader DrasilState [FS (repr (RenderFile repr))]
genConstMod = do
  cDesc <- modDesc $ liftS constModDesc
  liftS $ genModule "Constants" cDesc [] [genConstClass Pub]

genConstClass :: (ProgramSym repr) => ScopeTag ->
  Reader DrasilState (Maybe (CS (repr (Class repr))))
genConstClass scp = withReader (\s -> s {currentClass = cname}) $ do
  g <- ask
  let cs = constants $ csi $ codeSpec g
      genClass :: (ProgramSym repr) => [CodeDefinition] -> Reader DrasilState (Maybe 
        (CS (repr (Class repr))))
      genClass [] = return Nothing 
      genClass vs = do
        vals <- mapM (convExpr . codeEquat) vs 
        let vars = map (\x -> var (codeName x) (convType $ codeType x)) vs
            constVars = zipWith (constVarFunc (conRepr g) cname) vars vals
            getFunc Pub = publicClass
            getFunc Priv = privateClass
            f = getFunc scp
        cDesc <- constClassDesc
        cls <- f cDesc cname Nothing constVars (return [])
        return $ Just cls
  genClass $ filter (flip member (Map.filter (cname ==) (clsMap $ codeSpec g)) 
    . codeName) cs
  where cname = "Constants"

----- OUTPUT -------

genOutputMod :: (ProgramSym repr) => 
  Reader DrasilState [FS (repr (RenderFile repr))]
genOutputMod = do
  ofDesc <- modDesc $ liftS outputFormatDesc
  liftS $ genModule "OutputFormat" ofDesc [genOutputFormat] []

genOutputFormat :: (ProgramSym repr) => 
  Reader DrasilState (Maybe (MS (repr (Method repr))))
genOutputFormat = do
  g <- ask
  let genOutput :: (ProgramSym repr) => Maybe String -> Reader DrasilState 
        (Maybe (MS (repr (Method repr))))
      genOutput Nothing = return Nothing
      genOutput (Just _) = do
        let l_outfile = "outputfile"
            var_outfile = var l_outfile outfile
            v_outfile = valueOf var_outfile
        parms <- getOutputParams
        outp <- mapM (\x -> do
          v <- mkVal x
          return [ printFileStr v_outfile (codeName x ++ " = "),
                   printFileLn v_outfile v
                 ] ) (outputs $ csi $ codeSpec g)
        desc <- woFuncDesc
        mthd <- publicFunc "write_output" void desc parms Nothing 
          [block $ [
          varDec var_outfile,
          openFileW var_outfile (litString "output.txt") ] ++
          concat outp ++ [ closeFile v_outfile ]]
        return $ Just mthd
  genOutput $ Map.lookup "write_output" (eMap $ codeSpec g)
