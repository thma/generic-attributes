{-# LANGUAGE GADTs            #-}
{-# LANGUAGE RankNTypes       #-}
{-# LANGUAGE TypeApplications #-}

module RecordtypeReflection
  ( buildFromRecord,
    applyConstr,
    fieldValueAsString,
    fieldValues,
    gshow
  )
where

import           Control.Monad                  (zipWithM)
import           Control.Monad.Trans.Class      (lift)
import           Control.Monad.Trans.State.Lazy( StateT(runStateT), get, put )
import           Data.Data                      hiding (typeRep)
import           Data.Dynamic                   (Dynamic, fromDynamic, toDyn)
import           Data.List                      (elemIndex)
import           Database.HDBC                  (SqlValue, fromSql)
import           GHC.Data.Maybe                 (expectJust)
import           Type.Reflection                (SomeTypeRep (..), eqTypeRep,
                                                 typeRep)
import           TypeInfo                       
import           Data.Generics.Aliases          (extQ)

-- | A function that takes an entity and a field name as input parameters and returns the value of the field as a String.
--  Example: fieldValueAsString (Person "John" 42) "name" = "John"
--  Example: fieldValueAsString (Person "John" 42) "age" = "42"
--  if the field is not present in the entity, an error is thrown.
fieldValueAsString :: Data a => a -> String -> String
fieldValueAsString x field =
  valueList !! index
  where
    fieldList = fieldNames x
    valueList = fieldValues x
    index =
      expectJust
        ("Field " ++ field ++ " is not present in type " ++ typeName x)
        (elemIndex field fieldList)

-- | A function that take an entity as input paraemeter and returns a list of 
--   Strings representing the values of all fields of the entity.
--   Example: fieldValues (Person "John" 42) = ["John", "42"]
fieldValues :: (Data a) => a -> [String]
fieldValues = gmapQ gshow

buildFromRecord :: (Data a) => TypeInfo a -> [SqlValue] -> Maybe a
buildFromRecord ti record = applyConstr ctor dynamicsArgs
  where
    ctor = typeConstructor ti
    types = map fieldType (typeFields ti)
    dynamicsArgs =
      expectJust
        ("buildFromRecord: error in converting record " ++ show record)
        (zipWithM convert types record)

-- https://stackoverflow.com/questions/47606189/fromconstrb-or-something-other-useful
applyConstr :: Data a => Constr -> [Dynamic] -> Maybe a
applyConstr ctor args =
  let nextField :: forall d. Data d => StateT [Dynamic] Maybe d
      nextField = do
        as <- get
        case as of
          [] -> lift Nothing -- too few arguments
          (a : rest) -> do
            put rest
            case fromDynamic a of
              Nothing -> lift Nothing -- runtime type mismatch
              Just x  -> return x
   in case runStateT (fromConstrM nextField ctor) args of
        Just (x, []) -> Just x
        _            -> Nothing -- runtime type error or too few / too many arguments

-- | convert a SqlValue into a Dynamic value that is backed by a value of the type represented by the SomeTypeRep parameter.
--  If conversion fails, return Nothing.
--  conversion to Dynamic is required to allow the use of fromDynamic in applyConstr
--  see also https://stackoverflow.com/questions/46992740/how-to-specify-type-of-value-via-typerep
convert :: SomeTypeRep -> SqlValue -> Maybe Dynamic
convert (SomeTypeRep rep) val
  | Just HRefl <- eqTypeRep rep (typeRep @Int) = Just $ toDyn (fromSql val :: Int)
  | Just HRefl <- eqTypeRep rep (typeRep @Double) = Just $ toDyn (fromSql val :: Double)
  | Just HRefl <- eqTypeRep rep (typeRep @String) = Just $ toDyn (fromSql val :: String)
  | otherwise = Nothing


-- | Generic show: taken from syb package and https://chrisdone.com/posts/data-typeable/
gshow :: Data a => a -> String
gshow x = gshows x ""

gshows :: Data a => a -> ShowS
gshows = render `extQ` (shows :: String -> ShowS)
  where
    render t
      | isTuple =
          showChar '('
            . drop 1
            . commaSlots
            . showChar ')'
      | isNull = showString "[]"
      | isList =
          showChar '['
            . drop 1
            . listSlots
            . showChar ']'
      | otherwise =
          constructor
            . slots
      where
        constructor = showString . showConstr . toConstr $ t
        slots = foldr (.) id . gmapQ ((showChar ' ' .) . gshows) $ t
        commaSlots = foldr (.) id . gmapQ ((showChar ',' .) . gshows) $ t
        listSlots = foldr (.) id . init . gmapQ ((showChar ',' .) . gshows) $ t
        isTuple = all (== ',') (filter (not . flip elem "()") (constructor ""))
        isNull = all (`elem` "[]") (constructor "")
        isList = constructor "" == "(:)"