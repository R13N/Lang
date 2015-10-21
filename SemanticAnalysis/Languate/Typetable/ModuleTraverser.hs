module Languate.Typetable.ModuleTraverser (locallyDeclared, declaredType, declaredSuperType, constraintAdoptions) where

{-
Multiple functions to traverse the statements, in search for type declaration stuff
-}

import StdDef
import Exceptions
import Languate.CheckUtils

import Languate.Typetable.TypeLookupTable.TypeLookupTableDef
import Languate.Typetable.TypeLookupTable.TypeLookupTableUtils

import qualified Data.Map as M
import qualified Data.Set as S
import Data.Set hiding (map, filter)
import Data.Map hiding (map, filter, mapMaybe)
import Data.Maybe

import Languate.AST as AST
import Languate.TAST
import Languate.FQN
import Languate.Package


-- All locally declared types
locallyDeclared	:: Module -> [(Name, [Name], [TypeRequirement])]
locallyDeclared mod
		=  statements mod |> declaredType & catMaybes



declaredType :: Statement -> Maybe (Name, [Name], [TypeRequirement])
declaredType (ADTDefStm (ADTDef name frees reqs _ _))
		= Just (name, frees, reqs)
declaredType (SubDefStm (SubDef name _ frees _ reqs))
		= Just (name, frees, reqs)
declaredType (ClassDefStm classDef)
		= Just (name classDef, frees classDef, classReqs classDef)
declaredType _	= Nothing



declaredSuperType	:: TypeLookupTable -> Statement -> Exc [(RType, [Name], CType)]
declaredSuperType tlt (ADTDefStm (ADTDef nm frees reqs sums adopts))
	= do	-- the type being declared here is the supertype of the adopted types...
		super	<- resolveTypePath tlt ([], nm)
		-- ... applied on the frees of course!
		let super'	= applyTypeArgs super (frees |> RFree)
		adopts'	<- resolveTypes tlt adopts
		reqs'	<- resolveReqs tlt reqs
		adopts' |> (\typ -> (typ, frees, (super', reqs'))) & return
		{- whenever there are no constructors (and only a single adopted type),
			we declare a synonym; this case is handles elsewhere as to prevent supertype loops -}
declaredSuperType tlt (InstanceStm (Instance typePath frees super reqs))
	= do	typ	<- resolveTypePath tlt typePath
		let typ'= applyTypeArgs typ (frees |> RFree)
		super'	<- resolveType tlt super
		reqs'	<- resolveReqs tlt reqs
		(typ', frees, (super', reqs')) & return & return
declaredSuperType tlt (SubDefStm (SubDef name _ frees supers reqs))
	= do	typ	<- resolveTypePath tlt ([], name)
		supers'	<- resolveTypes tlt supers
		reqs'	<- resolveReqs tlt reqs
		supers' |> (\super -> (typ, frees, (super, reqs'))) & return
declaredSuperType tlt (ClassDefStm cd)
	= do	typ	<- ([], AST.name cd) & resolveTypePath tlt
		supers	<- subclassFrom cd & resolveTypes tlt
		reqs	<- classReqs cd & resolveReqs tlt
		let frees	=  AST.frees cd
		supers |> (\super -> (typ, frees, (super, reqs))) & return
declaredSuperType _ _	= return []


{-

cat A0 a:A1 a implies that A0 has the same constraints on 'a' as A1.
This function gives exactly this relation:
[A0 a, A1 a]

For CATEGORY-DECLARATIONS only, as the constraints imposed here are constraints to exist, not to have a certain supertype

-}
constraintAdoptions	:: TypeLookupTable -> Statement -> Exc [(RType, RType)]
constraintAdoptions tlt stm@(ClassDefStm _)
	-- ""cat X a:Y a"" : X (rt) only exists if the constraints on super are met
	= declaredSuperType tlt stm ||>> (\(rt, frees, (super, constraints)) -> (applyTypeArgs rt (frees |> RFree), super))
constraintAdoptions tlt stm@(ADTDefStm _)
	-- ""type X a={Constr} + Y a"": X (rt) only exists if the constraints on super are met
	= declaredSuperType tlt stm ||>> (\(super, frees, (rt, constraints)) -> (rt, applyTypeArgs super (frees |> RFree)))
constraintAdoptions _ _	= return [] 
