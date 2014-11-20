module Languate.TypeTable.TypeTable2MD where

{--
--}

import Data.Set as S
import Data.Map hiding (toList)
import Data.List hiding (lookup)
import Data.Maybe
import Prelude hiding (lookup)
import MarkDown
import Languate.TypeTable.TypeTable
import Languate.TypeTable.Expr2MD
import Languate.AST
import Languate.TAST
import StdDef


import Languate.FQN

typeTable2MD	:: FQN -> TypeTable -> MarkDown
typeTable2MD fqn tt
		= title 1 ("Type overview for "++show fqn) ++
			parag autogen ++
			knownTypes tt ++
			classesOverview tt


-- generates a nice table of types which are known in the module.
knownTypes	:: TypeTable -> MarkDown
knownTypes tt	= (title 2 $ "Known types") ++
			table ["Type","Typekind","Type Constraints","Synonym for","Supertypes","Comment"] (fmap (knownTypeRow tt) . toList $ known tt)

knownTypeRow	:: TypeTable -> (Type, Kind, Set TypeRequirement) -> [MarkDown]
knownTypeRow tt (t, kind, treq)
		=  [show t, show kind, typeReqs2MD $ S.toList treq,
			synonyms2md t tt ++ " " ++ revSynonyms2md t tt,
			commas . fmap show . S.toList . findWithDefault S.empty t $ supertypes tt,
			commentFor tt t]

synonyms2md	:: Type -> TypeTable -> MarkDown
synonyms2md t	=  fromMaybe "" . fmap show . lookup t . synonyms

revSynonyms2md	:: Type -> TypeTable -> MarkDown
revSynonyms2md t
		=  commas . fmap (ital . show) . S.toList . findWithDefault S.empty t . revSynonyms

commentFor	:: TypeTable -> Type -> MarkDown
commentFor tt t	=  let classes = instConstr tt in
		   fromMaybe "" $ fmap ((++) (ital "(Class)") . recode . classdocstr . fst) $ lookup t classes


classesOverview	:: TypeTable -> MarkDown
classesOverview tt	=  title 2 "Classes overview" ++ concatMap (flip classOverview tt) (keys $ instConstr tt)

-- assumes the given type is a class
classOverview	:: Type -> TypeTable -> MarkDown
classOverview t tt
		=  let (classdef, kind)	= findWithDefault (error "You passed a non-class thing into classOverview. Greets from TypeTable2MD") t $ instConstr tt in
			title 3 (show t)
			++ classInfo classdef t
			++ parag ("Kind: " `when` bold (if normalKind kind then "" else show kind))
			++ parag (recode $ classdocstr classdef)
			++ title 4 "Functions" ++ table ["Name","Type","Type Constraints","Comment"] (fmap showDecl $ decls classdef)
			++ title 4 "Laws" `when` itemize (fmap law2md $ classlaws classdef)


classInfo classdef t
		= let 	withFrees	= " " `when` unwords (frees classdef)
			superClass	= " in " `when` (commas $ fmap show $ subclassFrom classdef)
			typeReqs	= " where " `when` commas (fmap showTypeReq $ classReqs classdef) in
			parag (bold $ show t `when` (withFrees ++ superClass ++ typeReqs))


showDecl	:: (Name, Type, Maybe Comment, [TypeRequirement]) -> [MarkDown]
showDecl (n, t, mc, trs)
		=  [code n, show t, typeReqs2MD trs, recode $ fromMaybe "" mc]

autogen	= "This page is automatically generated. Do not edit it, as changes will get lost the next compilation."
