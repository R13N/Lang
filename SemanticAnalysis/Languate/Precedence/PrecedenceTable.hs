module Languate.Precedence.PrecedenceTable where

{--
This module implements the precedence table, a data structure which keeps track what associativity and precedence operators have.
--}

import StdDef
import Exceptions

import Data.Map hiding (map, foldr, null)
import Data.Set (member, Set)
import qualified Data.Set as S
import Prelude hiding (lookup)

import Data.Maybe

import Languate.FQN
import Languate.AST
import Languate.World

import Languate.Precedence.PrecTable2MD


type Operator	= Name
data PrecedenceTable	= PrecedenceTable { maxI::Int, op2i :: Map Operator Int, i2op :: Map Int (Set Operator), op2precMod :: Map Operator PrecModifier }

instance Show PrecedenceTable where
	show (PrecedenceTable _ op2i i2op mods)
		= precTable2md op2i i2op mods

modeOf	:: Int -> PrecedenceTable -> PrecModifier
modeOf index (PrecedenceTable _ _ i2op mods)
	= fromMaybe PrecLeft $ do	repr	<- lookup index i2op
					lookup (S.findMin repr) mods

precedenceOf	:: Expression -> PrecedenceTable -> Int
precedenceOf expr (PrecedenceTable tot op2i _ _)
		= if isOperator expr
			then	let (Operator nm)	= expr in
				findWithDefault tot nm op2i
			else	tot+1	-- plus 1, because normal expressions/function application have a precedence lower then unknown operators (tot+1)
