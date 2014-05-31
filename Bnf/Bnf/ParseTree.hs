module Bnf.ParseTree where

import Regex
import StdDef
import Bnf.FQN
import Data.Maybe
import Data.List (intersperse)
import Normalizable
import Control.Monad.Writer
{--

This module implements the basic ADT that represents a parse tree.
--}

type Line 	= Int
type Column 	= Int

-- a Coor represents info about the position (char in stream), line nr (how many lines have been passed) and column (the char line)
type Coor 	= (Pos, Line, Column)

-- info about a rule: what name it has, and what file it has been defined in
type RuleInfo	= (FQN, Name, Coor)

data ParseTree	= T RuleInfo String
		| S RuleInfo [ParseTree]


getContent	:: ParseTree -> String
getContent (T _ str)	= str
getContent (S _ pts)	= concatMap getContent pts

instance Normalizable ParseTree where
	normalize	= n

n	:: ParseTree -> ParseTree
n t@(T{})	= t
n (S i rs)	= S i $ filter (not . _isEmpty) $ map normalize rs

getName		:: RuleInfo -> Name
getName (_,name,_)	= name

-- gets the position of the leftmost token
getPosition	:: ParseTree -> Position
getPosition pt	=  let (_,_,(_,l,c))	= getFirstInf pt in
			(l,c)

getInf		:: ParseTree -> RuleInfo
getInf (T inf _)	= inf
getInf (S inf _)	= inf

getFirstInf	:: ParseTree -> RuleInfo
getFirstInf (S _ (pt:_))	= getFirstInf pt
getFirstInf (T inf _)	= inf

_isEmpty	:: ParseTree -> Bool
_isEmpty (S _ [])	= True
_isEmpty _		= False

cleanAll	:: [Name] -> ParseTree -> ParseTree
cleanAll ls	= cleanPt (`elem` ls)

cleanPt	:: (Name -> Bool) -> ParseTree -> ParseTree
cleanPt f	= filterPt (not . f)

filterPt	:: (Name -> Bool) -> ParseTree -> ParseTree
filterPt f (S inf subs)
		= S inf $ map (filterPt f) $ filter (f . getName . getInf) subs
filterPt _ token
		= token

instance Show ParseTree where
	show = _s


_s		:: ParseTree -> String
_s (T inf cont)	= "$"++ showInf inf ++ show cont
_s (S inf pts)	= "+"++ showInf inf ++ "\n" ++ add (concatMap (lines . _s) pts)


add		:: [String] -> String
add		=  concatMap (\str -> "  " ++ str ++ "\n")


sind		:: Int -> String
sind		=  flip replicate ' '


fill		:: Int -> String -> String
fill i str	=  replicate (i-length str) ' ' ++ str

showInf		:: RuleInfo -> String
showInf ri@(_,_,coor)	= showRI ri ++" "++ showCoor coor ++":    "


showRI		:: RuleInfo -> String
showRI (fqn, rule, _)
		=  show fqn++"."++rule


showCoor	:: Coor -> String
showCoor (_, l, c)
		= "line "++ fill 3 (show l)++", pos "++ fill 3 (show c)