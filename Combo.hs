{-# OPTIONS -fallow-undecidable-instances #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  XMonadContrib.Combo
-- Copyright   :  (c) David Roundy <droundy@darcs.net>
-- License     :  BSD-style (see LICENSE)
-- 
-- Maintainer  :  David Roundy <droundy@darcs.net>
-- Stability   :  unstable
-- Portability :  unportable
--
-- A layout that combines multiple layouts.
--
-----------------------------------------------------------------------------

module XMonadContrib.Combo (
                            -- * Usage
                            -- $usage 
                            combo
                           ) where

import Control.Arrow ( first )
import Data.List ( delete )
import Data.Maybe ( isJust )
import XMonad
import StackSet ( integrate, Stack(..) )
import qualified StackSet as W ( differentiate )

-- $usage
--
-- To use this layout write, in your Config.hs:
-- 
-- > import XMonadContrib.Combo 
-- 
-- and add something like
-- 
-- > combo (twoPane 0.03 0.5) [(full,1),(tabbed shrinkText defaultTConf,1)]
--
-- to your defaultLayouts.
--
-- The first argument to combo is a layout that will divide the screen into
-- one or more subscreens.  The second argument is a list of layouts which
-- will be used to lay out the contents of each of those subscreens.
-- Paired with each of these layouts is an integer giving the number of
-- windows this section should hold.  This number is ignored for the last
-- layout, which will hold any excess windows.

-- %import XMonadContrib.Combo
-- %layout , combo (twoPane 0.03 0.5) [(full,1),(tabbed shrinkText defaultTConf,1)]

combo :: (Eq a, Show a, Read a, ReadableSomeLayout a, Layout l (SomeLayout a, Int))
         => (l (SomeLayout a, Int)) -> [(SomeLayout a, Int)] -> Combo l a
combo = Combo []

data Combo l a = Combo [a] (l (SomeLayout a, Int)) [(SomeLayout a, Int)]
                 deriving ( Show, Read )

instance (Eq a, Show a, Read a, ReadableSomeLayout a, Layout l (SomeLayout a, Int))
    => Layout (Combo l) a where
    doLayout (Combo f super origls) rinput s = arrange (integrate s)
        where arrange [] = return ([], Just $ Combo [] super origls)
              arrange [w] = return ([(w,rinput)], Just $ Combo [w] super origls)
              arrange origws =
                do (lrs, msuper') <- runLayout super rinput (W.differentiate $ take (length origws) origls)
                   let super' = maybe super id msuper'
                       f' = focus s:delete (focus s) f
                       lwrs [] _ = []
                       lwrs [((l,_),r)] ws = [((l,r),differentiate f' ws)]
                       lwrs (((l,n),r):xs) ws = ((l,r),differentiate f' $ take len1 ws) : lwrs xs (drop len1 ws)
                           where len1 = min n (length ws - length xs)
                   out <- mapM (uncurry $ uncurry runLayout) $ lwrs lrs origws
                   let origls' = zipWith foo (out++repeat ([],Nothing)) origls
                       foo (_, Nothing) x = x
                       foo (_, Just l') (_, n) = (l', n)
                   return (concat $ map fst out, Just $ Combo f' super' origls')
              differentiate :: Eq q => [q] -> [q] -> Maybe (Stack q)
              differentiate (z:zs) xs | z `elem` xs = Just $ Stack { focus=z
                                                                   , up = reverse $ takeWhile (/=z) xs
                                                                   , down = tail $ dropWhile (/=z) xs }
                                      | otherwise = differentiate zs xs
              differentiate [] xs = W.differentiate xs
    modifyLayout (Combo f super origls) m =
                      do mls <- broadcastPrivate m (map fst origls)
                         let mls' = (\x->zipWith first (map const x) origls) `fmap` mls
                         msuper <- broadcastPrivate m [super]
                         case msuper of
                           Just [super'] -> return $ Just $ Combo f super' $ maybe origls id mls'
                           _ -> return $ Combo f super `fmap` mls'

broadcastPrivate :: Layout l b => SomeMessage -> [l b] -> X (Maybe [l b])
broadcastPrivate a ol = do nml <- mapM f ol
                           if any isJust nml
                              then return $ Just $ zipWith ((flip maybe) id) ol nml
                              else return Nothing
    where f l = modifyLayout l a `catchX` return Nothing
