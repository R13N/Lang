module Languate.File2Package where

{--

This module loads a module, looks at it's imports and loads unloaded stuff 

--}
import StdDef
import qualified Bnf
import Languate.FQN
import Languate.AST
import Languate.File2AST
import Data.Map hiding (null, map, filter)
import StateT
import Control.Monad
import Control.Monad.Trans
import Data.Maybe
import System.Directory

{- loads all modules needed for file. FQN is the name of the module that should be loaded, Filepath the path to 'src' in the project.
Imports of which the file was not found, are the second value in the tuple. It is a list, containing 
[this module wanted the import, this module was not found]
-}
loadPackage	:: FQN -> FilePath -> IO ([(FQN, Module)],[(FQN,FQN)])
loadPackage fqn src
		=  do	let FQN fqpn _ _	= fqn
			bnfs	<- loadBnf "../Parser/bnf/Languate.bnf"
			let ctx	= Context bnfs fqpn [(fqn, fqn)] empty src []
			(_, ctx)	<- runstateT loadRec ctx
			let notF	= notFound ctx
			return (toList $ loaded ctx, notF)

-- left fqn imports the right fqn
type ToLoad	= [(FQN,FQN)]
type Loaded	= Map FQN Module

-- not found: requestor -> missing request
data Context	= Context { bnfs :: Bnf.World, fqpn :: FQPN, toLoad:: ToLoad, loaded:: Loaded, root::FilePath, notFound::[(FQN,FQN)]}

-- loads as long as there are things in the toLoad-list
loadRec	:: StateT Context IO ()
loadRec	=  do	done	<- get' $ null . toLoad
		when (not done) $ do 	loadNext
					loadRec

loadNext	:: StateT Context IO ()
loadNext	=  do	request	<- pop
			cached	<- get' $ member (snd request) . loaded
			when (not cached) $ uncurry loadF request

loadF		:: FQN -> FQN -> StateT Context IO ()
loadF requestor fqn
		=  do	fpr	<- get' root
			let fp	=  fpr ++ relativePath fqn
			exists	<- lift $ doesFileExist fp
			if (not exists) then modify $ addNotFound requestor fqn
			else do bnf	<- get' bnfs
				modul	<- lift $ load bnf fp
				cache	<- get' loaded
				modify $ setLoaded $ insert fqn modul cache
				addImports fqn modul

-- adds all the imports to the toLoad-list
addImports	:: FQN -> Module -> StateT Context IO ()
addImports fqn mdul	
		=  do	fqnp	<- get' fqpn
			cache	<- get' loaded
			let fqns 	= map (import2fqn fqnp) $ imports' mdul
			let fqns'	= zip (repeat fqn) $ filter (`notMember` cache) fqns
			todolist	<- get' toLoad
			modify (setToLoad $ fqns' ++ todolist)
			
			
			

import2fqn	:: FQPN -> Import -> FQN
import2fqn fqpn (Import _ mods mod _w)
		= fromMaybe (error $ "Invalid import "++show mods ++ show mod) $ toFqn' fqpn mods mod

pop		:: StateT Context IO (FQN, FQN)
pop		=  do	ls	<- get' toLoad
			modify (setToLoad $ tail ls)
			return $ head ls

-- # Helper functions for lensing...

setLoaded	:: Loaded -> Context -> Context
setLoaded loaded (Context bnfs fqpn toLoad _ root errs)
		= Context bnfs fqpn toLoad loaded root errs

setToLoad	:: ToLoad -> Context -> Context
setToLoad toLoad (Context bnfs fqpn _ loaded root errs)
		= Context bnfs fqpn toLoad loaded root errs

addNotFound	:: FQN -> FQN -> Context -> Context
addNotFound requestor fqn (Context bnfs fqpn toLoad loaded root errs)
		= Context bnfs fqpn toLoad loaded root $ (requestor, fqn):errs

