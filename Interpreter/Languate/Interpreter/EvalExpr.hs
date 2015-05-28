module Languate.Interpreter.EvalExpr where

import StdDef
import Languate.Value
import Languate.TAST
import Languate.TableOverview
import Languate.FunctionTable
import Languate.BuiltIns

import Data.Map as M
import Data.List as L
import Data.Maybe

evalExpr	:: Evaluators -> Context -> TExpression -> Value
evalExpr f ctx nat@(TNat i)
	= ADT i (typeOf nat) []
evalExpr f ctx (TLocalCall nm tpinf)
	= let 	errMsg	=  "Local variable "++show nm++" not found" in
		ctx & localScope & findWithDefault (error errMsg) nm
evalExpr f ctx (TApplication typeInf e@(TCall sign) arg@(TNat i))
 | signFQN sign == builtInFQN
		= case signName sign of
			"construct"	-> ADT i typeInf []
			_		-> todos $ "Builtin "++signName sign
 | otherwise	= apply' f ctx e arg
evalExpr f ctx (TApplication typeInf func arg)
	= apply' f ctx func arg
evalExpr f ctx (TCall sign)
	= let	fqn	= signFQN sign
		-- the new context in which the clause should be evaluated
		ctx'	= ctx {location = fqn, localScope = M.empty}
		errMsg	= "No implementation table found for "++ show fqn
		impTbl	= ctx & package & implementations & unpackITS &
				M.findWithDefault (error errMsg) fqn & imps
		errMsg'	= "No implementation found for "++show sign
		clauses	= impTbl & M.findWithDefault (error errMsg') sign in
		evalThunk f $ Thunk $ zip (repeat ctx) clauses


-- When a thunk is ready for unpacking (no more needed args in head), it unpacks
evalThunk	:: Evaluators -> Value -> Value
evalThunk evals (Thunk ((ctx, TClause [] texpr):_))
		= (evalExpr' evals) ctx texpr
evalThunk _ v	= v

apply'		:: Evaluators -> Context -> TExpression -> TExpression -> Value
apply' f ctx texpr arg
		= let	valFun	= evalExpr f ctx texpr
			valArg	= evalExpr f ctx arg in
			apply f valFun valArg

apply		:: Evaluators -> Value -> Value -> Value
apply f (ADT i typeInfo args) arg
		= ADT i typeInfo (args++[arg])
apply f (Thunk clauses) arg
		= let clauses'	= clauses |> uncurry (evalClauses f arg) & catMaybes in
			if L.null clauses' then error $ "Pattern fallthrough. No clauses match!"
			else evalThunk f $ Thunk clauses'


evalClauses	:: Evaluators -> Value -> Context -> TClause -> Maybe (Context, TClause)
evalClauses f arg ctx (TClause (pat:pats) expr)
	= do	scope	<- (evalPattern' f) ctx arg pat
		let ctx'=  ctx {localScope = M.union scope $ localScope ctx}
		return $ (ctx', TClause pats expr)