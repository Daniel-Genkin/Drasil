{-# LANGUAGE TypeFamilies #-}

module Language.Drasil.Code.Imperative.GOOL.Symantics (
  -- Typeclasses
  PackageSym(..), AuxiliarySym(..)
) where

import Language.Drasil (Expr)
import Database.Drasil (ChunkDB)
import Language.Drasil.Code.DataDesc (DataDesc)
import Language.Drasil.CodeSpec (Comments, Verbosity)

import GOOL.Drasil (ProgData, GOOLState)

import Text.PrettyPrint.HughesPJ (Doc)

class (AuxiliarySym repr) => PackageSym repr where
  type Package repr 
  package :: ProgData -> [repr (Auxiliary repr)] -> 
    repr (Package repr)

class AuxiliarySym repr where
  type Auxiliary repr
  type AuxHelper repr
  doxConfig :: String -> GOOLState -> Verbosity -> repr (Auxiliary repr)
  sampleInput :: ChunkDB -> DataDesc -> [Expr] -> repr (Auxiliary repr)

  optimizeDox :: repr (AuxHelper repr)

  makefile :: [Comments] -> GOOLState -> ProgData -> repr (Auxiliary repr)

  auxHelperDoc :: repr (AuxHelper repr) -> Doc
  auxFromData :: FilePath -> Doc -> repr (Auxiliary repr)