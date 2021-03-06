module Languate.Parser.Pt2Import (pt2imp, pt2restrict, pt2idset) where

import StdDef
import Bnf.ParseTree
import Bnf hiding (simpleConvert)
import Languate.Parser.Utils
import Languate.AST

{--

This module converts the ParseTree into a function declaration, with laws etc.
Declarations may have multiple (explicit) types

--}

modName	= "Pt2Import"

pt2imp	:: ParseTree -> Import
pt2imp	=  pt2a h t s convert . cleanAll ["moduleSep"]

convert		:: AST -> Import
convert (Root asts)
		=  buildImport asts
convert ast	=  convErr modName ast


buildImport	:: [AST] -> Import
buildImport []	=  Import Private [] "" Nothing $ BlackList []
buildImport (PublicT:tail)
		= let Import _ path name pseudonym restrict = buildImport tail in
			Import Public path name pseudonym restrict
buildImport (ImportT:tail)
		= buildImport tail
buildImport (Path p:tail)
		= let Import public _ _ pseudonym restrict = buildImport tail in
			Import public (init' p) (last p) pseudonym restrict
buildImport (Restriction r:tail)
		= let Import public path name pseudonym _ = buildImport tail in
			Import public path name pseudonym r
buildImport (Alias pseudonym:tail)
		= let Import public path name _ r = buildImport tail in
			Import public path name (Just pseudonym) r
buildImport ast	=  convErr (modName++"-buildImport") $ Root ast

data AST	= ImportT
		| Ident Name
		| Path [Name]
		| Restriction Restrict
		| ParO	| ParC
		| PublicT
		| Root [AST]
		| AsT
		| Alias Name
	deriving (Show)


h		:: [(Name, ParseTree -> AST)]
h		=  [("limiters",Restriction . pt2restrict)]

t		:: Name -> String -> AST
t "globalIdent" id
		= Ident id
t _ "("		= ParO
t _ ")"		= ParC
t _ "as"	= AsT
t "import" "import"
		=  ImportT
t "import" "public"
		=  PublicT
t nm cont	=  tokenErr modName nm cont


s		:: Name -> [AST] -> AST
s _ asts@(Ident _:_)
		= Path $ accPath asts
s _ asts@(Path _:_)
		= Path $ accPath asts
s _ [AsT, Ident nm]
		= Alias nm
s _ [ast]	= ast
s _ asts	= Root asts

accPath		:: [AST] -> [Name]
accPath []	=  []
accPath (Ident id:tail)
		= id:accPath tail
accPath (Path ids:tail)
		= ids++accPath tail

-- ### Calculate the restrictions

pt2restrict	:: ParseTree -> Restrict
pt2restrict	=  pt2a [] tr sr convertR . cleanAll ["comma"]

pt2idset	:: ParseTree -> [Name]
pt2idset	=  pt2a [] tr sr convertIdSet . cleanAll ["comma"]

convertIdSet	:: ASTR -> [Name]
convertIdSet (Hide names)
		= names
convertIdSet (Show names)
		= names
convertIdSet (Asts asts)
		= getNames asts

data ASTR	= Idnt Name
		| Asts [ASTR]
		| HidingT
		| ShowingT
		| SetO	| SetC
		| ParOR	| ParCR
		| Hide [Name]
		| Show [Name]
	deriving (Show)

convertR	:: ASTR -> Restrict
convertR (Show nms)
		= WhiteList nms
convertR (Hide nms)
		= BlackList nms
convertR ast	=  convErr (modName++"-r") ast

tr		:: Name -> String -> ASTR
tr "localIdent" id
		= Idnt id
tr "globalIdent" id
		= Idnt id
tr "op" id
		= Idnt id
tr _ "{"	= SetO
tr _ "}"	= SetC
tr _ ")"	= ParOR
tr _ "("	= ParCR
tr _ "hiding"	= HidingT
tr _ "showing"	= ShowingT

tr nm cont	=  tokenErr (modName++"-r") nm cont

sr		:: Name -> [ASTR] -> ASTR
sr _ [ast]	= ast
sr _ (HidingT:tail)
		= Hide $ getNames tail
sr _ (ShowingT:tail)
		= Show $ getNames tail
sr _ asts	= Asts asts

getNames	:: [ASTR] -> [Name]
getNames []	=  []
getNames (Idnt name:tail)
		= name:getNames tail
getNames (Asts asts:tail)
		= getNames asts ++ getNames tail
getNames (_:tail)
		=  getNames tail
