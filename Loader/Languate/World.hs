module Languate.World (World, modules, importGraph', importGraph, aliasTables, buildWorld, module Languate.AliasTable)where

{--
This module provides the ''context''-datatype, which contains all commonly needed data of the currently compiling program.
--}

import StdDef
import Data.Map
import Languate.AST
import Languate.FQN
import Languate.AliasTable
import Data.Set as S
import qualified Data.Map as M

data World	= World 	{ modules	:: Map FQN Module
				, importGraph'	:: Map FQN (Map FQN Import)	-- this means: {module --> imports these, caused by this import statement}
				, aliasTables	:: Map FQN AliasTable	-- Alias table for each module. The aliastable contains what name maps on what module, e.g. "S" --> "Data.Set"; "AliasTable" --> "Languate.AliasTable", ... See aliastTable for more doc
				}
	deriving (Show)


importGraph	:: World -> Map FQN (Set FQN)
importGraph	=  M.map (S.fromList . keys) . importGraph'


buildWorld	:: Map FQN (Module, Set (FQN, Import)) -> World
buildWorld dict	= let 	modules		= fmap fst dict
			importGr	= fmap (merge . S.toList . snd) dict	:: Map FQN [(FQN, [Import])]
			importGr'	= fmap (M.fromList . fmap unp) importGr	:: Map FQN (Map FQN Import)
			aliastTables	= buildAliasTables $ fmap (S.fromList . M.toList) importGr' in
			World modules importGr' aliastTables
	where 	unp	(fqn, [imp])	= (fqn, imp)
		unp	(fqn, imps)	= error $ "Warning: double import. "++show fqn++" is imported by two or more import statements"
