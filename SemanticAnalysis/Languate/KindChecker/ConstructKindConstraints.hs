module Languate.KindChecker.ConstructKindConstraints where
{--
This module implements the functions which calculate what kind a declaration has.

This means that some kinds can only be known the moment the entire kind table is visible.

--}
import StdDef

import Languate.KindChecker.KindConstraint
import Languate.TAST
import Languate.AST
import Languate.FQN
import Languate.TypeTable

import Control.Monad.Reader
import Control.Arrow

import Data.Maybe

import Debug.Trace

data Info	= Info {fqn :: FQN, tlt :: TypeLookupTable}
type RI a	= Reader Info a

-- Kind of declares what relations of kinds between types exists. E.g. "Functor" has kind "a ~> b", "Maybe" has the same kind as "Functor" etc...
kindConstraintIn	:: Statement -> RI [KindConstraint]
kindConstraintIn (ADTDefStm (ADTDef name frees reqs _ _))
		= baseTypeConstr name frees reqs
kindConstraintIn (ClassDefStm classDef)
		= do	baseConstrs	<- baseTypeConstr (name classDef) (frees classDef) (classReqs classDef)
			base		<- resolve' (name classDef)
			constraints	<- subtypeConstraints base (frees classDef) (subclassFrom classDef)
			return $ baseConstrs ++ constraints
kindConstraintIn (InstanceStm (Instance id subtype reqs))
		= do	superT	<- resolve id
			subT	<- resolve subtype
			returnOne $ HaveSameKind subT superT
kindConstraintIn (SubDefStm (SubDef name _ frees superTypes reqs))
		= do	baseConstrs	<- baseTypeConstr name frees reqs
			subT	<- resolve' name
			constraints <- subtypeConstraints subT frees superTypes
			return $ baseConstrs ++ constraints
kindConstraintIn (SynDefStm (SynDef nm frees sameAs reqs))
		= do	baseConstrs	<- baseTypeConstr nm frees reqs
			synonym		<- resolve sameAs
			baseType	<- resolve' nm
			let base	= RApplied baseType $ map RFree frees
			let same	= HaveSameKind base synonym
			return $ same:baseConstrs
kindConstraintIn _	= return []


subtypeConstraints	:: RType -> [Name] -> [Type] -> RI [KindConstraint]
subtypeConstraints base frees superClasses
		= do 	superClasses	<- mapM resolve superClasses
			let appliedBase	= RApplied base $ map RFree frees
			return $ zipWith HaveSameKind (repeat appliedBase) superClasses

-- Constructs a basic 'has kind' relation, for the given (declared) name with it frees
baseTypeConstr	:: Name -> [Name] -> [TypeRequirement] -> RI [KindConstraint]
baseTypeConstr name frees reqs
		= do	base	<- resolve' name
			(curry, constr)	<- buildCurry frees reqs
			return $ HasKind base curry : constr

-- builds the kind, based on frees. e.g. ["k","v"] becomes '' * ~> * ~> * ''. This might cause addition constraints, e.g. k is ''Eq'' and ''Ord''. This means ''Eq'' and ''Ord'' should have the same kind too
buildCurry	:: [Name] -> [TypeRequirement] -> RI (UnresolvedKind, [KindConstraint])
buildCurry frees reqs
		= do	reqs'	<- resolveReqs reqs
			buildCurry' frees reqs'

buildCurry'	:: [Name] -> [(Name, RType)] -> RI (UnresolvedKind, [KindConstraint])
buildCurry' [] reqs
		=  return (UKind, [])
buildCurry' (n:nms) reqs
	= do	(tail, constrs)	<- buildCurry' nms reqs
		let reqs'	= merge reqs
		let found	= fromMaybe [] $ lookup n reqs'
		return $ if null found then (UKindCurry UKind tail, [])
				else (UKindCurry (SameAs $ head found) tail, constrs ++ zipWith HaveSameKind found (tail' found) )



-- util methods
resolve'	:: Name -> RI RType
resolve' name	=  do	lt 	<- asks tlt
			return $ resolveType' lt ([], name)

resolve		:: Type -> RI RType
resolve t	=  do	lt	<- asks tlt
			return $ resolveType lt t

resolveReqs	:: [TypeRequirement] -> RI [(Name, RType)]
resolveReqs rqs	=  do	lt	<- asks tlt
			return $ map (second (resolveType lt)) rqs


returnOne	:: a -> RI [a]
returnOne a	=  return [a]
