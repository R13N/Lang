module Bnf.Converter where

{--
This module implements helping methods to easily convert a parse tree into a abstract parse tree
--}

import Control.Monad.Writer
import Bnf.BNF
import Bnf.ParseTree
import StdDef

{-
Convert takes 3 other functions:
The tokenizer (t), the sequence reduction (r) and the hooks.
A tokenizer takes a rulename and a string and converts it to an cpt. 
	It has the chance to give errors and warnings, which are all accumulated.
	Note that the AST keeps getting build even if an error is reported. this is so that different errors could get reported in one execution; this also means you should provide an error value in your cpt.

The sequence reductor gets a rulename and a sequence of cpts (that are generated by the other functions) and should generate an ast too. You might want to be error resilient.
	The same rules for passing errors and warnings applyx


h/hooks: 

-}

type Warning	= (RuleInfo, String)
type Error	= (RuleInfo, String)

type Errors	= [Either Warning Error]

type ErrorMsg	= String
type WarningMsg	= String

type Message	= Maybe (Either WarningMsg ErrorMsg)

simpleConvert	:: (Name -> ParseTree -> Maybe (Writer Errors cpt))
			-> (Name -> String -> cpt)
			-> (Name -> [cpt] -> cpt)
			-> ParseTree -> Writer Errors cpt
simpleConvert h t s
		= convert h (lft2 t) (lft2 s)

lft2	:: (a -> b -> c) -> a -> b -> (Maybe d,c)
lft2 f a b	= (Nothing, f a b)

convert	:: (Name -> ParseTree -> Maybe (Writer Errors cpt)) -> 
		(Name -> String -> (Message, cpt)) -> 
		(Name -> [cpt] -> (Message, cpt)) -> ParseTree -> Writer Errors cpt
convert hooks tokens seqs pt@(T inf@(_,name,_) str)
	= doHook (hooks name pt) (takeMsg inf $ tokens name str)
convert hooks tokens seqs pt@(S inf@(_,name,_) pts)
	= doHook (hooks name pt) (do	converted	<- mapM (convert hooks tokens seqs) pts
					takeMsg inf $ seqs name converted)

doHook	:: Maybe (Writer Errors cpt) -> Writer Errors cpt -> Writer Errors cpt
doHook (Just hook) _
	= hook
doHook Nothing cpt	= cpt

takeMsg	:: RuleInfo -> (Message, cpt) -> Writer Errors cpt
takeMsg	_ (Nothing, cpt)	= return cpt
takeMsg inf (Just msg, cpt)
		= do	addMsg inf msg
			return cpt
addMsg	:: RuleInfo -> Either WarningMsg ErrorMsg -> Writer Errors ()
addMsg inf (Left warning)	= tell [Left (inf, warning)]
addMsg inf (Right error)	= tell [Right (inf, error)]

