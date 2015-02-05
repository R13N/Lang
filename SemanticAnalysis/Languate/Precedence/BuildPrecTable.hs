module Languate.Precedence.BuildPrecTable where

{--
This module builds the precedence table, step by step.
--}

import StdDef
import State
import Languate.AST

import Data.Map hiding (union, map, filter, null, foldr)
import qualified Data.Map as Map
import Data.Maybe
import Prelude hiding (lookup)
import Data.List (nub)

import Control.Arrow
import Data.Tuple


import Debug.Trace

{- checks if a ''(+) < (-)'' relation does not exist if ''(+) = (-)'' is defined somewhere. Thus, if two operators are in the same union, checks no LT-relation exists between them.
Returns faulty arguments.
-}

checkIllegalLT	:: [(Name, Name)] -> Map Name Name -> [(Name,Name)]
checkIllegalLT ltRels dict
		=  let canons	= map (canonLT dict) ltRels in
		   let zipped	= zip ltRels canons in
			map fst $ filter (isSame . snd) zipped
			where isSame (o1,o2)	= o1 == o2



-- ### Building of actual table


-- actual construction of a "PrecedenceTable"-datastructure is done in 'PrecedenceTable.hs'. This here does the heavy lifting.
buildTable	:: [Name] -> [Name] -> Map Name Name -> (Map Name Int, Map Int [Name])
buildTable repres allOps unions
		=  let repres'	= zip repres [1..] in
		   let prec 	= (fromList repres', fromList $ map (\(o,i) -> (i,[o])) repres') in
			foldr (\op acc -> addOp op unions acc) prec allOps


addOp		:: Name -> Map Name Name -> (Map Name Int, Map Int [Name]) -> (Map Name Int, Map Int [Name])
addOp op unions	(dict, dict')
		=  let	repres	= fromJust $ lookup op unions in
		   let i	= fromJust $ lookup repres dict in
			(insert op i dict, insertLst i op dict')


-- ### Building of partial and ordering

{-
 Makes a list of {"a" --> ["b","c"], "b" --> ["c"], "c" --> []}, which means that "a" should be evaluated after ["b","c"].
The first one in the list will thus be "c", which has no elements it should wait for.

 Gives a partial ordering by removing representative operations step by step.

Might get in a _loop_, e.g. on {"a" -> ["a"]}. This should not happen when the input is a union find input.
--}
buildOrdering	:: (Map Name [Name], Map Name [Name]) -> [Name]
buildOrdering rels@(ltRel, _)
		=  	let highestPreced	= emptyKey ltRel in
			if null highestPreced then	checkCycle ltRel -- either we're done or are stuck on a loop.
				else 	let op 	= head highestPreced in
					op : buildOrdering (removeGroup op rels)

checkCycle	:: Map Name [Name] -> [Name]
checkCycle dict	=  if Map.null dict then [] else error $ "Precedence building: stuck in a loop! "++show dict

-- > {"a" --> ["b","c"],"b" --> ["c"], "c" --> []}, {"c" --> ["a","b"], "b" --> "a"}
-- The second relation in the tuple is the 'reverse relation'. This means we can use that to quickly shorten lists.
removeGroup	:: Name -> (Map Name [Name], Map Name [Name]) -> (Map Name [Name], Map Name [Name])
removeGroup o (ltRel, revRel)
		= let 	toRems	= fromMaybe [] $ lookup o revRel in
			(delete o $ foldr (deleteFromLst o) ltRel toRems, revRel)

-- searches for entries with empty keys
emptyKey	:: Map Name [Name] -> [Name]
emptyKey dict	=  map fst $ filter (null . snd) $ toList dict

-- assumes each element points to it's smallest representative
neededGroups	:: Map Name Name -> Int
neededGroups dict
		=  let reprs	= map snd $ toList dict in
			length $ nub reprs

-- writes the tuple as their representative
canonLT		:: Map Name Name -> (Name,Name) -> (Name, Name)
canonLT dict (o1, o2)
		=  fromJust $ do	r1	<- lookup o1 dict
					r2	<- lookup o2 dict
					return (r1,r2)

ltGraph		:: [(Name,Name)] -> (Map Name [Name], Map Name [Name])
ltGraph rels	=  let allOps	= concatMap (\(n1,n2) -> [n1,n2]) rels in
		   let startDict	= fromList $ zip allOps (repeat []) in
			snd $ runstate (mapM_ collectGT rels) (startDict, startDict)

{- collect gt adds the right argument to the list of the first. This way, we can see immediatly which has a class that is bigger
It does the reverse for the second map
-}
collectGT	:: (Name, Name) -> State (Map Name [Name], Map Name [Name]) ()
collectGT (o1,o2)
		=  do	modify $ first $ insertLst o1 o2
			modify $ second $ insertLst o2 o1
