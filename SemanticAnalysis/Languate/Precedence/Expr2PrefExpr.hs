module Languate.Precedence.Expr2PrefExpr where

{- This module converts an AST.Expression into an AST.expression where all operator invocations are replaced by a prefix call notation, according to the precedence.

> True && False = (&&) True False
> !True && !False	= (&&) ((!) True) ((!) False)
> !True * False + False	= (+) ((*) ((!) True) False) False
etc...

How do we do this? First, we split the flat expression ''1 + 1 * 2'' into parts. We get the lowest class, and recursively bring the part left and right into prefix form.

-}

import StdDef
import Languate.AST
import Languate.Precedence.PrecedenceTable
import Data.Maybe
import Prelude hiding (lookup)
import Data.Map hiding (filter, map)

import Normalizable


expr2prefExpr		:: PrecedenceTable -> Expression -> Expression
expr2prefExpr t (Seq exprs)
			= normalize $ makePref t $ map (expr2prefExpr t) exprs
expr2prefExpr t (Tuple exprs)
			= Tuple $ map (expr2prefExpr t) exprs
expr2prefExpr _ e	= e

makePref	:: PrecedenceTable -> [Expression] -> Expression
makePref tb exprs
	| not $ any isOperator exprs
	 	=  Seq exprs
	| otherwise
		= mp tb exprs

mp	:: PrecedenceTable -> [Expression] -> Expression
mp pt@(PrecedenceTable _ op2i i2op modifs) exprs
	= let index	= minimum $ map (\(Operator k) -> fromJust $ lookup k op2i) $ filter isOperator exprs in		-- minimum index = should be executed as last
	  let mode	= modeOf index pt in
	  let seq	= filter (Seq [] /= ) $ map normalize $ splitSeq pt index exprs in
		bringInPrefix mode seq

{-
Split sec is more or less the core of the algorithm.
It takes the first n expressions, where no operator of level i exists. This block will be passed to a new makePref.
A list formed as [Expression, Operator, Expression, Operator, ...] will be returned, which is ready to place in prefix notation.
-}
splitSeq	:: PrecedenceTable -> Int -> [Expression] -> [Expression]
splitSeq pt i exprs
		= let (init, tail)	= break (\e -> i == precedenceOf e pt) exprs in
		  let head	= makePref pt init in
		  let tail'	= reSplitSeq pt i tail in
			head:tail'

reSplitSeq	:: PrecedenceTable -> Int -> [Expression] -> [Expression]
reSplitSeq pt i []	= []
reSplitSeq pt i (op@(Operator _):tail)
		= op:splitSeq pt i tail


bringInPrefix	:: PrecModifier -> [Expression] -> Expression
bringInPrefix _ [expr]	= expr
bringInPrefix PrecPrefix (Operator nm:exprs)
		= let expr =	bringInPrefix PrecPrefix exprs in
			Seq [Call nm, expr]
bringInPrefix PrecPrefix exprs	= error $ "Prefix usage on more than one argument: "++show exprs
bringInPrefix PrecLeft (e1:Operator nm:e2:rest)
		= bringInPrefix PrecLeft ( Seq [Call nm, e1, e2] : rest)
bringInPrefix PrecPostfix (expr:Operator nm:rest)
		= bringInPrefix PrecPostfix $ Seq [Call nm, expr]:rest
bringInPrefix PrecRight (e1:Operator nm: rest)
		= let e2	= bringInPrefix PrecRight rest in
			Seq [Call nm, e1, e2]