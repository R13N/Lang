module Languate.MarkUp.MarkUp where

-- This module implements the base definitions of the markup data structure

import StdDef
import State
import Data.Maybe
import Data.List

-- Represents a snippet of markUpped code
data MarkUp
        = Base String		            -- Embeds a plaintext in markup
        | Parag MarkUp                  -- Paragraph for markup
        | Seq [MarkUp]                  -- Sequence of markup
        | Emph MarkUp		            -- Emphasized markup
        | Imp MarkUp 		            -- Important markup
        | Code MarkUp 		            -- Code section
        | Incorr MarkUp 	            -- Incorrect code
        | Titling MarkUp MarkUp         -- Embedded titeling [title, markup]
        | Link MarkUp URL               -- A link with overlay text [markup, url]
	| InLink MarkUp Name		-- A link to a document within the cluster
        | Table [MarkUp] [[MarkUp]]     -- A table [header, tablerows]
        | List [MarkUp]                 -- Unordered list
        | OrderedList [MarkUp]          -- Ordered list
	| Embed Name			-- Embeds the document from the cluster into this markup

type URL = String

data MarkUpStructure
	= Str (String -> MarkUp) String
	| One (MarkUp -> MarkUp) MarkUp
	| Two (MarkUp -> MarkUp -> MarkUp) MarkUp MarkUp
	| Multi ([MarkUp] -> MarkUp) [MarkUp]
	| ExtraString (MarkUp -> String -> MarkUp) MarkUp String
	| TableStructure [MarkUp] [[MarkUp]]

-- A general function which extract the markdown into it's constructor + args, within the structure
unpack	:: MarkUp -> MarkUpStructure
unpack (Base str)
	= Str Base str
unpack (Parag mu)
	= One Parag mu
unpack (Seq mus)
            = Multi Seq mus
unpack (Emph mu)
            = One Emph mu
unpack (Imp mu)
            = One Imp mu
unpack (Code mu)
            = One Code mu
unpack (Incorr mu)
            = One Incorr mu
unpack (Titling title mu)
            = Two Titling title mu
unpack (Link mu url)
            =  ExtraString Link mu url
unpack (Table mus muss)
            = TableStructure mus muss
unpack (List mus)
            = Multi List mus
unpack (OrderedList mus)
            = Multi OrderedList mus
unpack (InLink mu url)
	    = ExtraString InLink mu url
unpack (Embed url)
	    = Str Embed url

-- rebuild the markup from its structure
repack	:: (MarkUp -> MarkUp) -> MarkUpStructure -> MarkUp
repack f (Str cons str)	= cons str
repack f (One cons mu)	= cons $ f mu
repack f (Two cons mu0 mu1)
			= cons (f mu0) (f mu1)
repack f (Multi cons mus)
			= mus |> f & cons
repack f (ExtraString cons mu str)
			= cons (f mu) str
repack f (TableStructure mus muss)
			= Table (mus |> f) (muss ||>> f)

-- Traverses the MarkUp. When on a node a 'a' is found, this a is returned. Children of this node  are not traversed
search	:: (MarkUp -> Maybe a) -> MarkUp -> [a]
search f mu	= fromMaybe (unpack mu & flatten >>= search f) (f mu |> (:[]))

flatten	:: MarkUpStructure -> [MarkUp]
flatten (Str _ _)	= []
flatten (One _ mu)	= [mu]
flatten (Two _ mu0 mu1)	= [mu0, mu1]
flatten (Multi _ mus)	= mus
flatten (ExtraString _ mu _)
			= [mu]
flatten (TableStructure mus muss)
			= mus ++ concat muss


rewrite     :: (MarkUp -> Maybe MarkUp) -> MarkUp -> MarkUp
rewrite f mu = fromMaybe (repack (rewrite f) $ unpack mu) (f mu)

------ EASY ACCESS FUNCTIONS -------

parag  = Parag . Base
emph   = Emph . Base
imp    = Imp . Base
code   = Code . Base
incorr = Incorr . Base
titling str
       = Titling (Base str)
link str
       = Link (Base str)
inlink str
	= InLink (Base str) str
notImportant
	= emph	-- TODO change to actual not important
