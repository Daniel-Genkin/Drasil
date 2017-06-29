-- Standard code to make a table of symbols.
module Drasil.Sections.TableOfSymbols 
  (table) where

import Data.Maybe (isJust)
import Data.Drasil.Utils(getS)

import Language.Drasil
import qualified Data.Drasil.Concepts.Math as CM
import Data.Drasil.Concepts.Documentation
 
--Removed SymbolForm Constraint and filtered non-symbol'd chunks 
-- | table of symbols creation function
table :: (Quantity s) => [s] -> (s -> Sentence) -> Contents
table ls f = Table 
  [at_start symbol_, at_start description, at_start' CM.unit_]
  (mkTable
  [(\ch -> (\(Just t) -> (getS t)) (getSymb ch)),
  f, 
  unit'2Contents]
  sls)
  (titleize tOfSymb) False
  where sls = filter (isJust . getSymb) ls --Don't use catMaybes

-- ^. defn