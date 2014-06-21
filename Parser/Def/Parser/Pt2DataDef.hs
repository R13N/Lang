module Def.Parser.Pt2Function (pt2func) where

import StdDef
import Bnf.ParseTree
import Bnf
import Control.Monad.Writer
import Control.Monad
import Def.Parser.Utils
import Def.Parser.Pt2Prelude
import Def.Parser.Pt2Type
import Def.Parser.Pt2Expr
import Def.Parser.Pt2Pattern
import Def.Parser.Pt2Comment
import Def.Def

{--

This module converts the ParseTree into a ADT-declaration.
It parses stuff as

data ADT	= Sum Bool Int
		| Prod 

See comments in the bnf for exact syntax and docstring locations

--}

modName	= "Pt2Function"

pt2func	:: ParseTree -> 
pt2func	=  pt2a h t s convert . cleanAll ["nl"]

convert		:: AST -> Expression
convert ast	=  convErr modName ast


data AST	= Declaration Name Type
		| LawAst Law
		| Comm [Comment]
		| Line [Pattern] Expression
	deriving (Show)


h		:: [(Name, ParseTree -> AST)]
h		=  []

t		:: Name -> String -> AST
t nm cont	=  tokenErr modName nm cont


s		:: Name -> [AST] -> AST
s _ [ast]	= ast
s nm asts	= seqErr modName nm asts



