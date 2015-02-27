module Languate.TypeTable.Bind.Bind where

{--
This module implements a simple bind, which works on Full Super Type Tables
--}

import StdDef

import Languate.Graphs.DirectedGraph

import Data.Map hiding (foldr)
import qualified Data.Map as M
import Data.Set hiding (foldr)
import qualified Data.Set as S
import qualified Data.List as L
import Data.Tuple
import Data.Maybe
import Data.Either
import Prelude hiding (fail, lookup)

import StateT

import Languate.TAST
import Languate.TypeTable

import Control.Monad hiding (fail)
import Control.Monad.Trans

import Debug.Trace


{-

Binds t0 in t1. If binding succeeds, this means t0 is a subtype (or equal type) of t1.

For each applied type, at most one supertypetable convert can happen.

Binding via requirements can happen too.
When free ''a'' is bound against free ''b'', each requirement on ''a'' is matched on each requirement on ''b''.

Assumes that t0 has no overlapping free names with t1.
-}
bind	:: TypeTable -> Map Name [RType] -> RType -> RType -> Either String Binding
bind tt reqs t0 t1
	= let 	ctx	= Context reqs tt noBinding
		msg	= "While binding "++show t0++" in "++ show t1 in
		runstateT (inside msg $ bind' t0 t1) ctx |> snd |> binding



bind'	:: RType -> RType -> StMsg ()
bind' (RFree a) (RFree b)
 = do	aReqs	<- requirementsOn a
	bReqs	<- requirementsOn b
	addBinding (b, RFree a)
	-- bind each aReq against each bReq. Each bReq should be filled in with at least one aReq
	succ	<- mapM (\b -> mapM (\a -> succeeded $ bind' a b) aReqs) bReqs
	-- internal list: bind each aReq against a bReq. One match is enough
	-- extarnal list: each bReq is tried. All should have a match
	let ok	= succ |> or & and
	assert ok $ "Could not bind the free '"++a++"' against the free '"++
		b++"' as '"++b++"' has some requirements that '"++a++"' can't meet." ++
		indent ("'"++a++"': "++show aReqs++"\n'"++b++"': "++show bReqs)
bind' t0 (RFree b)
 = do	bReqs	<- requirementsOn b
	addBinding (b, t0)
	inside ("While binding "++show t0++" against the type requirements on '"++b++"'") $
		mapM_ (bind' t0) bReqs
bind' (RCurry t0 t1) (RCurry t0' t1')
 = do	bind' t0 t0'
	bind' t1 t1'
bind' t0@(RNormal fqn nm) t1
 = when (t0 /= t1) $	-- if they are the same, nothing should happen
	-- we search if t1 is a supertype of t0
	inside "Could not bind" $ do
	let tid0	= (fqn, nm)
	tid1	<- getBaseTID t1 ? (show t1 ++ " is not a simple type.")
	sst	<- get' typeT |> spareSuperTypes |> findWithDefault M.empty tid0
	-- possibleSupers	:: [RType]
	posSups	<- lookup tid1 sst ? (show t1++" is not a supertype of "++show t0++"\n"++show sst)
	-- we try to match any supertype. All tried and failed types are returned.
	failed	<- whileM (\posSup -> fmap not $ succeeded $ bind' posSup t1) posSups
	-- if all types have failed, length failed = length posSups
	assert (length failed /= length posSups) $
		"No possible supertypes could be bound in "++show t1++".\nTried types:\n"++indent (show posSups)
bind' t0@(RApplied bt at) t1@(RApplied bt' at')
 = do	bind' bt bt'
	bind' at at'



{- Tries to bind the (bt,at) of a applied type against a given rtype, by using the full super type table

-}
bapp	:: (RType, RType) -> RType -> StMsg ()
bapp (bt,at) t1
	= todo


{- Tries to make two types the same, by filling in the frees in any of them.

Unificate is associative.

Type requirements and supertypes are **not** taken in account here.

Used in "add binding", if conflicting values could be added

-}
unificate	:: RType -> RType -> Either String Binding
unificate t0 t1
	| t0 == t1	= return noBinding
	| otherwise	= let 	ctx	= Context M.empty (error "No tt needed for unify!") noBinding
				res	= runstateT (unificate' t0 t1) ctx in
				res |> snd |> binding

unificate'	:: RType -> RType -> StMsg ()
unificate' (RFree a) (RFree b)
	= unless (a == b) $ do
		addBinding (a, RFree b)
		addBinding (b, RFree a)
unificate' (RFree a) t1
	= addBinding (a,t1)
unificate' t0 (RFree b)
	= addBinding (b,t0)
unificate' (RCurry t0 t1) (RCurry t0' t1')
	= do	unificate' t0 t0'
		unificate' t1 t1'
unificate' (RApplied bt at) (RApplied bt' at')
	= do	unificate' bt bt'
		unificate' at at'
unificate' t0 t1
	= assert (t0 == t1) $ "Could not unify "++ st True t0 ++" and "++ st True t1



data Context	= Context 	{ frees		:: Map Name [RType]	-- keeps track of the supertypes (= requirements) for a given free. All bound frees should be included.
				, typeT 	:: TypeTable
				, binding 	:: Binding
				}

-- the monad we'll work with
type StMsg a	= StateT Context (Either String) a




-----------
-- UTILS --
-----------


requirementsOn	:: Name -> StMsg [RType]
requirementsOn a
	= get' frees |> findWithDefault [] a


fstt	:: TypeID -> StMsg FullSuperTypeTable
fstt tid
	= do	mFstt	<- get' typeT |> allSupertypes |> lookup tid
		assert (isJust mFstt) $ "No full super type table found for "++show tid
		return $ fromJust mFstt


sstt	:: TypeID -> StMsg SpareSuperTypeTable
sstt tid
	= do	spareSTT	<- get' typeT |> spareSuperTypes |> lookup tid
		assert (isJust spareSTT) $ "No spare STT for "++show tid
		return $ fromJust spareSTT


addBinding	:: (Name, RType) -> StMsg ()
addBinding (n,t)
	= do	ctx	<- get
		let (Binding b)	= binding ctx
		-- check wether or not a conflicting binding exists
		let previous	= M.lookup n b
		assert (isNothing previous || t == fromJust previous) $
			"Conflicting bindings for '"++n++"' are found."++
			" It could be both bound to "++show (fromJust previous)++" and "++show t
		put $ ctx {binding = Binding $ M.insert n t b}

addFrees	:: [Name] -> StMsg ()
addFrees bound
	= do	ctx	<- get
		let frees'	= foldr (\n -> M.insert n []) (frees ctx) bound
		put $ ctx {frees = frees'}



fail		:: String -> StMsg a
fail		=  lift . Left


assert True _	= return ()
assert False msg	= fail msg


catch		:: a -> StMsg a -> StMsg a
catch backup stmsg
	= do	ctx	<- get
		case runstateT stmsg ctx of
			(Left _)	-> return backup
			(Right (a, ctx))	-> put ctx >> return a


try		:: StMsg a -> StMsg a -> StMsg a
try first backup
	= do	ctx	<- get
 		case runstateT first ctx of
			Left msg	-> backup
			Right (a, ctx')	-> put ctx' >> return a

inside		:: String -> StMsg a -> StMsg a
inside msg m	=  do	ctx	<- get
			case runstateT m ctx of
				Left msg'	-> fail $ msg++":\n"++msg'
				Right (a,ctx')	-> put ctx' >> return a

-- Tries the given action. If it fails, rolls back the binding and returns false
succeeded	:: StMsg a -> StMsg Bool
succeeded m	= catch False (m >> return True)

(?)	:: Maybe a -> String -> StMsg a
(?) Nothing
	= fail
(?) (Just a)
	= const $ return a

joinEither	:: [Either String b] -> Either String [b]
joinEither []	= Right []
joinEither (Left str:rest)
	= case joinEither rest of
		Left msg	-> Left $ str++"; "++msg
		Right _		-> Left str
joinEither (Right b:rest)
	= case joinEither rest of
		Left msg	-> Left msg
		Right bs	-> Right (b:bs)




instance Show Context where
	show (Context frees _ b)= "Context "++sd frees ++ ", "++show b
