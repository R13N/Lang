module Languate.AST.ModuleAST where

{--

This module implements the data structures representing statements and modules.

--}

import StdDef
import Languate.AST.TypeAST
import Languate.AST.TypeASTUtils
import Languate.AST.FunctionAST
import Languate.AST.FunctionASTUtils

import Data.Either (rights)

type Line	= Int
type Column	= Int
type Coor	= (Line, Column)
data Module	= Module {moduleName::Name, exports::Restrict, imports::Imports, statements'::[(Statement, Coor)]}
	deriving (Show)


statements	= map fst . statements'

-- ## Stuf about imports

-- for comments hovering around imports
type Imports	= [Either Comment (Import, Coor)]

imports''	:: Module -> [(Import, Coor)]
imports'' 	=  rights . imports

imports'	:: Module -> [Import]
imports'	=  map fst . imports''


type Pseudonym	= Name
-- represents an import statement. public - Path - ModuleName - pseudonym = name as which the module has been imported - restrictions
data Import	= Import Visible [Name] Name (Maybe Pseudonym) Restrict
	deriving (Show, Ord, Eq)
-- restrict is the blacklist/whitelist of the showing/hiding in an import statement. Can contain both function/operator names and type names
data Restrict	= BlackList [Name] | WhiteList [Name]
	deriving (Show, Ord, Eq)


data Statement	= FunctionStm 	Function
		| ADTDefStm	ADTDef
		| SynDefStm	SynDef
		| SubDefStm	SubDef
		| ClassDefStm	ClassDef
		| InstanceStm 	Instance
		| Comments [Comment]
		| ExampleStm	Law
		| AnnotationStm	Annotation
	deriving (Show)

isAllowed	:: Restrict -> Name -> Bool
isAllowed (BlackList items)
		= not . (`elem` items)
isAllowed (WhiteList items)
		= (`elem` items)

-- function declarations in module, which are public/private
functions	:: Visible -> Module -> [(Name, Type, [TypeRequirement])]
functions mode mod
		= let 	restrict	= exports mod
			stms	= statements mod in
		  _censor ((mode == Public) ==) restrict $ concatMap _unpackF stms

_censor		:: (Bool -> Bool) -> Restrict -> [(Name, Type, [TypeRequirement])] -> [(Name, Type, [TypeRequirement])]
_censor inv restrict
		= filter (\(nm,_,_) -> inv $ isAllowed restrict nm)



_unpackF	:: Statement -> [(Name,Type, [TypeRequirement])]
_unpackF (FunctionStm f)
		= signs f
_unpackF (ClassDefStm cd)
		= fmap (\(nm,t,_,tr) -> (nm,t,tr)) $ decls cd
_unpackF _	= []
