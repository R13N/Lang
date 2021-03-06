module Languate.AST.TypeAST where

{--

This module implements the AST-data structures of all type related and meta things:

Types themself, ADT-definitions, class definitions, instance declarations and subtype declarations.

Notice: all utility functions (show, normalize, ...) are implemented in TypeASTUtils.

It also contains meta things, as laws, comments, docstrings
--}

import StdDef
import Normalizable

type Line	= Int
type Column	= Int
type Coor	= (Line, Column)

-- ## META STUFF
data Law	= Law 	{ lawName		:: Maybe Name
			, lawDeclarations	:: [(Name, [Type])]
			, typeReqs		:: [TypeRequirement]
			, expr1 		:: Expression
			, expr2 		:: Expression }
		| Example (Maybe Name) Expression Expression	-- can be interpreted easily
	deriving (Ord, Eq)

type Comment	= String
-- a comment just before any declaration, (thus with no newlines in between)
data DocString a	= DocString {comment::Comment, about::a}
	deriving Show

data Annotation	= Annotation Name String	-- a 'normal' annotation. See docs in the BNF
data PrecedenceAnnot
		= PrecAnnot {operator::Name, modif::PrecModifier, relations::[PrecRelation]}

data PrecModifier	= PrecLeft | PrecRight | PrecPrefix | PrecPostfix
	deriving (Eq)

data PrecRelation	= PrecEQ Name Name
			| PrecLT Name Name


-- ## EXPRESSIONS

data Visible	= Private
		| Public
	deriving (Show, Eq, Ord)


data Expression	= Nat Int
		| Flt Float
		| Chr Char
		| Seq [Expression]
		| Tuple [Expression]
		| BuiltIn String (Type, [TypeRequirement])	-- Calls a built-in function, e.g. 'toString',
		| Cast Type	| AutoCast
		| Call String
		| Operator String
		| ExpNl (Maybe Comment)	-- a newline in the expression, which might have a comment
	deriving (Ord, Eq)
{- Expression which only contains calls (which has been passed through the precedencerebuild)
	Only gets used from semantic analysis
-}
type OperatorFreeExpression	= Expression

-- ## TYPE STUFF

-- The data structure representing a type in Languate. Probably one of the most important definitions!
data Type	= Normal [Name] Name	-- A normal type, e.g. Bool. Extra names are to disambiguate, e.g. Data.Bool vs Postgres.Bool or something (if that actually happens with postgres, i'll kill them)
		| Free String	-- A 'free' type, such as 'a', 'b'. (e.g. in id : a -> a)
		| Applied Type [Type]
		| Curry [Type]
		-- represents a tuple type. When the types are converted to fully qualified types, the actual tuple type is used.
		| TupleType [Type]
		-- gets used e.g. in ''map : (a -> b) -> Mappable (_:a) -> Mappable c''
		| DontCareType
	deriving (Eq, Ord)

{- The data structure representing a type requirement of the form "a has a supertype Ord".
When no special requirement is present, nothing is used.
-}
type TypeRequirement	= (Name, Type)



-- ADTDefs --
-------------

{-
Represents an ADT in languate.
ADTDef "TypeName" ["Free", "type","variable","names"] [TReqs] [sums]

> data List a  = Cons a (List a) | Nil
becomes : ADTDef "List" [("a", Nothing)] "Comment about a list" product
> data NaiveDict a b	= [a,b]ADT
> data BalancedTreeDict (a in Eq) b	= ...
becomes
ADTDef "Dict" ["k","v"] [("k","Ord")] product

The docstring is saved within the statements
-}
data ADTDef	= ADTDef Name [Name] [TypeRequirement] [ADTSum]


{-
A single constructor is represented by a single ADTSum-object.
The needed types are the last argument, they might (or might not) have a name
e.g.
> data ADT	= A x:Int Float	-- docstring for A
ADTSum "A" Visible (Just "docstring for A") [(Just "x", "Int"),(Nothing, "Float")]
-}
data ADTSum	= ADTSum Name Visible [(Maybe Name, Type)]


-- Synonym and subtyping --
---------------------------

{-
> type Name = String.
> type SortedSet (a:Ord)	= {a}
  SynDef "SortedSet" ["a"] (Applied (Normal "Set") (Free "a")) [("a"), Normal "Ord"]
   no obligated docstring for this one! -}
data SynDef	= SynDef Name [Name] Type [TypeRequirement]

{-
Data type representing a subtype declaration, e.g.
> subtype Nat	= Int
Might have multiple supertypes
> subtype Nat'	= NatInf & Nat
> subtype Name = String -- see bnf for usage
> subtype TenSet (a in Ord)	= ...
no obligated docstring for this one! -}
data SubDef	= SubDef Name Visible [Name] [Type] [TypeRequirement]

-- ## Creating classes and instances

-- Name: name of the new class; second Name: name of it in the functions; [(Name,Type)]: declarations
data ClassDef	= ClassDef
			{ name		:: Name
			, frees		:: [Name]
			, classReqs	:: [TypeRequirement]
			, subclassFrom	:: [Type]
			, classlaws	:: [Law]
			, decls		:: [(Name,[Type], [TypeRequirement])] }
	deriving (Ord, Eq)

-- Instance: (["Collection"],"Set") ["a"] ---is--- "Show" [("a","Show")]
data Instance	= Instance ([Name],Name) [Name] Type [TypeRequirement]
