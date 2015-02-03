module Languate.TypeTable.IsSuperType where

{--
Implementation of the supertype check.
--}


import StdDef
import Languate.TypeTable
import Languate.TAST
import Normalizable
import Data.Map (Map, findWithDefault)
import Data.Set (Set, empty, member)
import qualified Data.Set as S
import Data.Map (Map, fromList, toList, keys, lookup)
import qualified Data.Map as M
import Prelude hiding (lookup)
import Data.Maybe
import Data.Either
import Data.List (nub)

import Control.Monad.Trans
import Control.Arrow
import StateT

import Debug.Trace



{- Tries to bind t0 in t1.

bind "A" "a"	= {a --> A}
bind "A" "B"	= {} if B is a supertype of A	== if A has a superType B
			failure otherwise
bind "Curry X Y" "a -> b"
		= {a --> X, b --> Y}

Important: the requirement-table should contain **each bound free**, to prevent double binding.

-}

bind	:: TypeTable -> Map Name [RType] -> RType -> RType -> Either String Binding
bind tt reqs
	= bind' (Context reqs tt noBinding)


bind' ctx t0 t1
	= runstateT (b' t0 t1) ctx |> snd |> binding

b'	:: RType -> RType -> StMsg ()
b' t0 t1
	= let (t0', t1')	= (normalize t0, normalize t1) in
		if t0' == t1' then return ()
			else b t0' t1'

b	:: RType -> RType -> StMsg ()
b t (RFree a)
	= do	reqs	<- requirementsOn a
		ctx	<- get
		allSupers	<- allSuperTypesOf t
		let unmetReqs	= filter (`notElem` allSupers) reqs
		if null unmetReqs then addBinding (a, t) else do
		failed $ "Could not bind "++show t++" to "++a++", type requirement is not met: "++show unmetReqs
b t0 t1@(RNormal _ _)
	= do	supers0	<- allSuperTypesOf t0
		if t1 `elem` supers0 then return ()
		else failed $ "Could not bind "++show t0++" against "++show t1



superTypesOf	:: RType -> StMsg [RType]
superTypesOf (RNormal fqn nm)
	= fetchSTF (fqn, nm)  |> findWithDefault S.empty [] |> (S.map fst) |> S.toList
superTypesOf (RFree a)
	= requirementsOn a
superTypesOf (RApplied t [])
	= superTypesOf t
superTypesOf (RApplied t args)
	= do	baseSupers	<- allSuperTypesOf (RApplied t $ tail' args)
		argSupers	<- mapM allSuperTypesOf args -- e.g. [[a,Eq,Ord], [b]]
		let mixedSupers	= perms $ baseSupers:argSupers-- e.g. [[a,b], [Eq, b], [Ord, b]]
		mapM appliedSuperTypes mixedSupers |> concat





{-
e.g.
"Collection" "a" -> Monoid, Eq (if a is Eq)
"Collection" "Eq"

-}
appliedSuperTypes	:: [RType] -> StMsg [RType]
appliedSuperTypes (base:args)
	= appSuper base args



-- Given the base type and arguments, will try to give each super type
appSuper	:: RType -> [RType] -> StMsg [RType]
appSuper t@(RNormal fqn nm) args
	= do	sttf	<- fetchSTF (fqn, nm)
		ctx		<- get
		-- kys = all free variables with exactly enough applied
		let kys	=  filter ((==) (length args) . length) $ keys sttf
		-- list of: (appliedFrees "a" "b", [(superType, ifTheseReqsAreMet)])
		let supers	= map (\k -> (k,S.toList $ findWithDefault (error "Huh?") k sttf)) kys
		let supers'	= mapMaybe (validateArgs ctx args) $ unmerge supers
		return $ trace (show t ++ show args ++ "--> "++show supers') supers'


-- Returns the supertype if the requirements (of the args) are met
validateArgs	:: Context -> [RType] -> ([Name], (RType, Map Name [RType])) -> Maybe RType
validateArgs ctx args (freeNames, (superT, reqs))
	= if validateKeys ctx args freeNames  reqs
		then Just superT
		else Nothing

{-
The supertypetable says:
if a is Eq, then Collection a is Eq
This checks wether [Int] [a] {a --> Eq} is fullfilled, thus if Int is a Eq
-}
validateKeys	:: Context -> [RType] -> [Name] -> Map Name [RType] -> Bool
validateKeys ctx args names reqs
	= let	reqsFor a	= findWithDefault [] a reqs
		namedArgs	= zip args names
		argsWithReqs	= map (second reqsFor) namedArgs in	-- e.g. (Int, [Eq]), meaning: Int should be EQ
		all (uncurry $ validateReqs ctx) argsWithReqs



{- Validates a binding.
Given a type t and a set of types it should be, returns True if t fulfills the reqs.
-}
validateReqs	:: Context -> RType -> [RType] -> Bool
validateReqs ctx t reqs
		= let 	bindings	= map (bind' ctx t) reqs
			failedBindings	= length $ lefts bindings in
			failedBindings == 0



allSuperTypesOf	:: RType -> StMsg [RType]
allSuperTypesOf (RApplied t [])
	= allSuperTypesOf t
allSuperTypesOf t
	= do	supers	<- superTypesOf t -- TODO fix leak! Supertype could be "List a", where "a" suddenly got captured!
		supers'	<- mapM allSuperTypesOf supers |> concat
		return $ supers ++ supers'
