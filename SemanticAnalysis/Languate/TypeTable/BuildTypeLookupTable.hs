module Languate.TypeTable.BuildTypeLookupTable where

{-
This module provides functions to
	-> Calculate what types are declared in a module
	-> What types are public in a module
	-> Get the aliastable
	-> For Module M, expand the aliastable
 -}

import qualified Data.Map as M
import qualified Data.Set as S
import Data.Set hiding (map, filter)
import Data.Map hiding (map, filter)
import Data.Maybe
import Data.Tuple
import Control.Arrow (first, second)
import Data.List
import Languate.AST
import StdDef

import Languate.World
import Languate.FQN
import Languate.TypeTable
import Languate.ImportTable.ExportCalculator

import Debug.Trace


{-
Building of a type lookup table:


-> we build a simple set with what locally declared types (correctness doesn't matter)
	-> we filter what types are public (according to the functions)
-> we calculate the export and imports for each module (exportCalculator)
-> We build the ''TypeLookupTable''
	-> We can resolve type calls of give an error when ambiguity arises
	-> All this information condenses into the 'TypeLookupTable'
-}


-- {FQN (1) --> {FQN (2) --> Name (3)}}: This fqn (1) exports these type(names) (3), which are originally declared on location (2). E.g. {"Prelude" --> {"Data.Bool" --> "Bool", "Num.Nat" --> "Nat", "Num.Nat" --> "Nat'", ...}, ...}
type Exports	= Map FQN (Map FQN (FQN, Name))

--buildTLTs	:: World -> Map FQN TypeLookupTable
buildTLTs world	=  let	modules	= Languate.World.modules world
			injectSet a	= S.map (\b -> (a,b))
			injectSetFunc f fqn	= injectSet fqn $ f fqn
			pubLocDecl	= injectSetFunc $ publicLocallyDeclared world
			locDecl		= injectSetFunc $ locallyDeclared world
			exports = calculateExports' world pubLocDecl (reexportType world)
			imports = calculateImports' world locDecl exports					in
			mapWithKey (buildTLT  world imports) $ aliasTables world

{- builds a TLT for a certain module.

Type resolving is done against the module it was declared in (and no explicit module).

import Data.Bool showing (Bool)
import Data.StrictList (StrictList, List)
-- List is declared in Data.List
import Idiots.TheirList (TheirList, List)
-- List is declared in Idiots.List

Valid:
Bool, Bool.Bool, Data.Bool.Bool
StrictList, StrictList.StrictList, Data.StrictList.StrictList
StrictList.List
Idiots.List.List
Data.List.List

invalid:
List.List, List : ambiguous to both idiots and data.

The package is named Idiots, as EVERYONE SHOULD ALWAYS USE STANDARD LISTS FOR CONSISTENCY AND CODE REUSABILITY!

-}
buildTLT	:: World -> Map FQN {-Module we are interested in-} (Set ((FQN, Name) {-Type declaration + origin-}, FQN{-Imported via. Can be self-}))
			-> FQN {-What we have to build TLT for-}
			-> AliasTable
			-> TypeLookupTable
buildTLT world imps mod at
	= let	declared	= S.map fst $ findWithDefault S.empty mod imps	:: Set (FQN, Name) {-Name, declared in -}
		localDecl	= locallyDeclared world mod	:: Set Name {- The locally declared types -}
		locDeclDict	= S.toList $ S.map (\nm -> (([], nm), mod)) localDecl	in
		addAll locDeclDict $ S.foldl (addLookupEntry at) M.empty declared


addLookupEntry	:: AliasTable -> TypeLookupTable -> (FQN, Name) -> TypeLookupTable
addLookupEntry at tlt (declaredIn, name)
		= addAll [((p, name), declaredIn) | p <- tails $ fwd "at" declaredIn at] tlt


addAll		:: (Ord k, Ord v) => [(k,v)] -> Map k (Set v) -> Map k (Set v)
addAll pairs dict
		= Prelude.foldr addOne dict pairs


addOne		:: (Ord k, Ord v) => (k,v) -> Map k (Set v) -> Map k (Set v)
addOne (k,v) dict
		= M.insert k (S.insert v $ findWithDefault S.empty k dict) dict


-- A type is publicly declared if: 1) at least one public function uses it or 2) not a single private function uses it. (e.g. declaration without usage in the module)
publicLocallyDeclared	:: World -> FQN -> Set Name
publicLocallyDeclared w fqn
		= let	mod 		= fwd "modules" fqn $ modules w
			localDeclared	= locallyDeclared w fqn
			publicTypes	= functions Public  mod >>= allTypes >>= usedTypes
			privateTypes	= functions Private mod >>= allTypes >>= usedTypes
			isPublic nm	= nm `elem` publicTypes || nm `notElem` privateTypes  in
				S.filter isPublic localDeclared


locallyDeclared	:: World -> FQN -> Set Name
locallyDeclared	w fqn
		=  S.fromList $ Data.Maybe.mapMaybe declaredType $ statements $ fwd "modules" fqn $ modules w

declaredType	:: Statement -> Maybe Name
declaredType (ADTDefStm (ADTDef name _ _ _ _))
		= Just name
declaredType (SynDefStm (SynDef name _ _ _))
		= Just name
declaredType (SubDefStm (SubDef name _ _ _ _ ))
		= Just name
declaredType (ClassDefStm classDef)
		= Just $ name classDef
declaredType _	= Nothing


{-
Should we reexport the given type?

A type is reexported if: it is publicly imported.
No code for locally declared stuff, done in publicLocallyDeclared

args:
- FQN1 : the current node we are at
- (FQN	: The node which (directly) imports the type
  , (FQN, Name))	: The declared type + where it was defined
A type is publicly REexported if: 1) at least one public function uses it or 2) the import was public (and the type not restricted)

-}
reexportType	:: World -> FQN -> (FQN, (FQN, Name)) -> Bool
reexportType w curMod (impFrom, (_,typeName))
		= let	-- current module
			modul	= fwd "modules" curMod $ modules w
			-- imported nodes
			imps	= fwd "IG" curMod $ importGraph' w
			-- Import statement through which the type got imported. If public: reexp
			err0	= error $ "Compiler bug: semantal/BuildTLT: we got an import here without import statement! "++show impFrom++" supposedly imported by "++show curMod
			(Import vis _ _ _ restrict)	= findWithDefault err0 impFrom imps
			exportAllowed	= vis == Public && isAllowed restrict typeName		in
			exportAllowed



allTypes	:: (Name, Type, [TypeRequirement]) -> [Type]
allTypes (_,t,treqs)
		= t : map snd treqs

err str fqn 	= error $ "Building type lookup table: fqn not found: "++show fqn++" within "++str++" table"
fwd str fqn	= findWithDefault (err str fqn) fqn
