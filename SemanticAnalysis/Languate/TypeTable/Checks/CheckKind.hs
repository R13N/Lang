module Languate.TypeTable.Checks.CheckKind where

{--
This module implements various checks on kinds. It provides helper functions for the kindsolver.
--}

import StdDef
import MarkDown
import Exceptions
import Languate.CheckUtils

import Data.Map hiding (map, filter)
import Prelude hiding (lookup)
import Data.Set (Set)
import qualified Data.Set as S
import Data.List (intercalate)

import Languate.AST
import Languate.TAST
import Languate.TypeTable
import Languate.FQN
import Languate.TypeTable.KindChecker.KindConstraint

import Languate.Graphs.SearchCycles


{-Validates wether the 'HaveSameKind'-constraints are met-}
validateSameKindConstraints	:: KindLookupTable -> Map Name Kind -> ((RType, RType), Location) -> Check
validateSameKindConstraints klt frees ((rt0, rt1),loc)
			= onLocation loc $ inside "Kind constraint error" $
			  do	k0	<- kindOf klt frees rt0
				k1	<- kindOf klt frees rt1
				let s t k	= show t ++ " :: \t"++show k
				assert (k0 == k1) $ "Types which are used to denominate a free should have the same kind. Found types:\n" ++
					s rt0 k0 ++"\n"++s rt1 k1


{-Code to report cycles-}
reportCycles	:: Map (FQN, Name) (Set (FQN, Name)) -> Check
reportCycles graph
		= let	cycles	= cleanCycles graph in
			mapM_ reportCycle cycles

filterCycles	:: [(FQN, Name)] -> [SimpleConstraint'] -> [SimpleConstraint']
filterCycles inCycle
		= filter (\((id,_),_) -> id `notElem` inCycle)

reportCycle	:: [(FQN, Name)] -> Check
reportCycle [a,_]
		= err $ "Could not construct the infinite type "++showTypeID a++". Please remove the dependency (in the type requirements) on itself."
reportCycle (typ:path)
		= err $ indent' ("Could not construct the kind for "++ showTypeID typ ++", as this type has a cyclic dependency") $
				intercalate " -> " $ map showTypeID path

cyclesIn	:: [SimpleConstraint] -> Map (FQN, Name) (Set (FQN, Name))
cyclesIn	=  searchCycles . fromList . map buildDeps


buildDeps	:: SimpleConstraint -> ((FQN, Name), (Set (FQN, Name)))
buildDeps (id, uk)
		= (id, S.fromList $ dependsOn uk)



{-Over application checks -}

reportOverApplication	:: KindLookupTable -> SimpleConstraint' -> Check
reportOverApplication klt (((fqn, nm), uk), coor)
		= inFile fqn $ onLine coor $ checkUKOverApp klt uk

checkUKOverApp	:: KindLookupTable -> UnresolvedKind -> Check
checkUKOverApp _ UKind	= pass
checkUKOverApp klt (UKindCurry k1 k2)
			= checkUKOverApp klt k1 >> checkUKOverApp klt k2
checkUKOverApp klt (SameAs rtype)
			= do	kindOf klt empty rtype
				return ()


{- Checks types are correctly applied. E.g. ''Functor Int Int'' does not make sense, just as Functor -> Monad.

Checks performed:
- Over application
- Wrong Kind application (e.g. expected a type of Kind (* ~> *), but one of a different kind is given)
- Under application (if you want to get the kind of a partially applied type function, use ''kindOf'')

Not checked here/Assumptions
- Undeclared frees, all frees should be declared at this point. (Frees not provided in the table will be treated as having kind '*')

Args:
- KLT
- Free map. Gives the kind of the known frees, e.g. {a --> "*", c --> "* ~> *"}
- Applied type, e.g. "Functor a String b" (obviously fualty)
-}
checkKindApp	:: KindLookupTable -> Map Name Kind -> RType -> Check
checkKindApp klt frees rtype
		=  inside ("In the kind application of "++show rtype) $
			do	kind	<- kindOf klt frees rtype
				assert (0 == numberOfKindArgs kind) $ "Expecting " ++ number (numberOfKindArgs kind) ++ " more type arguments to "++show rtype



-- Gets the correct kind of a type (including applications), or an error message. Kinds might not be fully applied.
kindOf		:: KindLookupTable -> Map Name Kind -> RType -> Exceptions' String Kind
kindOf klt _ (RNormal fqn nm)
		= lookup (fqn, nm) klt ? ("Kind of the type "++show fqn++"."++nm++" was not found")
kindOf _ frees (RFree a)
		= lookup a frees ? ("Free type variable '"++a++"' was not found.\nMake sure it is declared before used (thus left of it's usage)")
kindOf klt frees t@(RApplied bt at)
		= do	bk	<- kindOf klt frees bt
			ak	<- kindOf klt frees at
			let msg	= "In the type application "++ pars (show t) ++" "++ pars (show at)
			inside msg $ applyKind t bk (ak, at)
kindOf klt frees (RCurry at rt)
		= do	let msg t k 	= "The type "++show t++" should be fully applied as it is used in a curry, but it has the kind "++show k
			ak	<- kindOf klt frees at
			assert (ak == Kind) $ msg at ak
			rk	<- kindOf klt frees rt	-- calculate the kind of the rest, which should be fully applied too
			assert (rk == Kind) $ msg rt rk
			return Kind
kindOf klt frees (RTuple tps)
		= do	kind	<- mapM (kindOf klt frees) tps
			mapM (\(k,t) -> assert (k == Kind) $ "The type "++show t++" should be fully applied as it is used in a tuple, but it has the kind "++show k) $
					zip kind tps
			return Kind




-- Applies the first kind to given arguments. e.g. (* ~> (* ~> *) ~> *) $ [(* ~> *), (* ~> *)] is a valid application giving *
applyKind	:: RType -> Kind -> (Kind,RType) -> Exceptions' String Kind
applyKind baseType Kind _
		= do	err $ "Type overapplication:\n"++
				show baseType ++ " was applied to too much type arguments"
		 	return Kind
applyKind baseType bk@(KindCurry k rest) (argK,argT)
		= do	assert (sameStructure k argK) $
				"Kind mismatch: could not unify "++show k++" and "++show argK++".\n"++
				"The type "++show argT ++ "::" ++ show argK ++" was applied to "++show baseType ++ "::" ++ show bk
			return rest

sameStructure	:: Kind -> Kind -> Bool
sameStructure Kind Kind	= True
sameStructure (KindCurry k0 k1) (KindCurry k0' k1')
		= sameStructure k0 k0' && sameStructure k1 k1'
sameStructure _ _	= False
