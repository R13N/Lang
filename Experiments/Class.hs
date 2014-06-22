module Class where

{--

This module implements 

--}

class Lst l where
	merge	:: l a -> l a -> l a


data L1 a = C a (L1 a) | Merge (L1 a) (L1 a)| Nil
data L2 a = A a (L2 a) | M (L2 a) (L2 a) | Null

instance Lst L1 where
	merge l1 l2	= Merge l1 l2

instance Lst L2 where
	merge l1 l2	= M l1 l2
