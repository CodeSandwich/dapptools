{-# LANGUAGE GADTs #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE DataKinds #-}

{- | An embedding of the SMT2 typing rules in the haskell type system

     SMT2 scripts are made up of sequences of solver commands. These commands
     can declare new variables and assert statements about these variables.

     Each node in the script AST is assigned a type that represents the
     available typing context. Any attempt to extend the script with a new
     command will produce a type error if any sub term references a variable that
     has not yet been declared.
-}
module SMT2 where

import Prelude hiding (Eq,Word)
import GHC.TypeLits
import Data.Kind
import Data.Function
import Control.Monad.State


-- base types --------------------------------------------------------------------------------------


-- | Atomic data types
data Atom = Boolean

-- | Define the haskell datatype used to declare literals of a given atomic type
type LitType :: Atom -> Type
type family LitType a where
  LitType Boolean = Bool

-- | Singleton type for Atom
data SAtom (a :: Atom) where
  SBool :: SAtom Boolean

-- | The typechecking environment
type Env = [(Symbol, Atom)]


-- name declaration --------------------------------------------------------------------------------


-- | Extends the typechecking env with (name, typ) iff name is not already present in env
type Decl name typ env = DeclH name typ env env

type DeclH :: Symbol -> Atom -> Env -> Env -> Env
type family DeclH name typ env orig where
  DeclH name typ '[] orig = '(name, typ) : orig
  DeclH name _ ('(name, _) : _) _ = TypeError (Text "\"" :<>: Text name :<>: Text "\" is already declared")


-- environment lookup ------------------------------------------------------------------------------


-- | A proof that (name, typ) is present in a given env
data Elem :: Symbol -> Atom -> Env -> Type where
  DH :: Elem name typ ('(name, typ) : tl)
  DT :: Elem name typ tl -> Elem name typ (hd : tl)

-- | Compile time type env lookup
type Find :: Symbol -> Atom -> Env -> Elem n t e
type family Find name typ env where
  Find name typ ('(name,typ) : _) = DH
  Find name typ ('(_,_): tl) = DT (Find name typ tl)
  Find name typ '[] = TypeError (Text "\"" :<>: Text name :<>: Text "\" is undeclared")

-- | Found resolves iff it is passed a valid prood of inclusion in a given typechecking env
class Found (proof :: Elem name typ env) where
instance Found DH where
instance (Found tl) => Found (DT tl) where

-- | Type alias for adding an inclusion constraint against a given typing env
type Has name typ env = Found (Find name typ env :: Elem name typ env)


-- SMT2 AST ----------------------------------------------------------------------------------------


-- | The language of top level solver commands
data SMT2 (e :: Env) where
  EmptySMT2 :: SMT2 '[]

  Declare   :: KnownSymbol n
            => SAtom t
            -> SMT2 e
            -> SMT2 (Decl n t e)

  Assert    :: Exp e Boolean
            -> SMT2 e
            -> SMT2 e

  CheckSat  :: SMT2 e
            -> SMT2 e


-- | The language of assertable statements
data Exp (e :: Env) (t :: Atom) where

  -- polymorphic
  Lit       :: LitType t -> Exp e t
  Var       :: (KnownSymbol n, Has n t e) => Exp e t
  ITE       :: Exp e Boolean   -> Exp e t -> Exp e t -> Exp e t

  -- boolean
  And       :: [Exp e Boolean] -> Exp e Boolean
  Or        :: [Exp e Boolean] -> Exp e Boolean
  Eq        :: [Exp e Boolean] -> Exp e Boolean
  Xor       :: [Exp e Boolean] -> Exp e Boolean
  Impl      :: [Exp e Boolean] -> Exp e Boolean
  Distinct  :: [Exp e Boolean] -> Exp e Boolean


-- monadic interface -------------------------------------------------------------------------------


data Dict :: Env -> Type where
   Nil  :: Dict '[]
   (:>) :: Entry name typ -> Dict tl -> Dict ('(name, typ) : tl)

infixr 5 :>

data Entry :: Symbol -> Atom -> Type where
  E :: forall name typ. SAtom typ -> Entry name typ


insert :: SomeSymbol -> Atom -> Dict env -> (Dict (Decl name typ env), Elem name typ env)
insert name typ env = undefined

type Dyn e a = State (Dict e, SMT2 e) a


--declare :: String -> Dyn e (SMT2 e)
declare name = do
  (env, smt) <- get
  pure EmptySMT2


-- tests -------------------------------------------------------------------------------------------

testDyn :: Dyn '[] (SMT2 '[])
testDyn = do
  pure EmptySMT2


-- TODO: writing out the full typechecking env here is very annoying.
-- Why doesn't the following work?
-- test :: SMT2 e
test :: SMT2 '[ '( "hi", Boolean ) ]
test
  = EmptySMT2
  & Declare @"hi" SBool
  & Assert (Var @"hi")

  -- produces a type error: "hi" is already declared
  -- & Declare @"hi" SBool

  -- produces a type error: "yo" is undeclared
  -- & Assert (Var @"yo")

  & CheckSat

-- asserting the typechecking env for fragments works
incomplete :: (Has "hi" Boolean e) => SMT2 e -> SMT2 e
incomplete = Assert (And [Var @"hi", Lit False])
