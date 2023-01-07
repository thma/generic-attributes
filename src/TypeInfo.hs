module TypeInfo
  ( 
    TypeInfo(..) 
  , FieldInfo(..)
  , typeInfo
  , fieldInfo
  , fieldValueAsString
  , fieldNames
  , fieldNamesFromTypeInfo
  , fieldValues
  , gshow
  , applyConstr
  ) where
    
import Data.Data -- (Data, gmapQ, dataTypeOf, dataTypeConstrs, typeOf, Constr, TypeRep, constrFields)
import           Data.Generics.Aliases (extQ)
import Data.Maybe (fromMaybe)
import Data.List (elemIndex)
import Data.Dynamic (Dynamic, fromDynamic, toDyn)
import Control.Monad.Trans.State.Lazy
import Control.Monad.Trans.Class (lift)

{--

https://chrisdone.com/posts/data-typeable/

--}
    
data FieldInfo = FieldInfo
  { fieldName :: Maybe String   -- ^ The name of the field, Nothing if it has none.
  , fieldConstructor :: Constr  -- ^ The type of the field.
  } deriving (Show)
    
data TypeInfo = TypeInfo
  { typeName :: TypeRep       -- ^ The name of the type.
  , typeConstructor :: Constr -- ^ The constructors of the type.
  , typeFields :: [FieldInfo] -- ^ The fields of the type.
  } deriving (Show)
  
typeInfo :: Data a => a -> TypeInfo  
typeInfo x = TypeInfo
  { typeName = typeOf x
  , typeConstructor = toConstr x
  , typeFields = fieldInfo x
  } 

-- | A function that returns a list of FieldInfos representing the name and type of each field in a data type.
fieldInfo :: (Data a) => a -> [FieldInfo]
fieldInfo x = zipWith FieldInfo names types
  where
    constructor = head $ dataTypeConstrs $ dataTypeOf x
    candidates = constrFields constructor
    types = gmapQ toConstr x
    names = if length candidates == length types
              then map Just candidates
              else replicate (length types) Nothing

-- | Reflection tools
fieldNamesFromTypeInfo :: TypeInfo -> [String]
fieldNamesFromTypeInfo ti = map (fromMaybe (error errMsg) . fieldName) (typeFields ti)
  where errMsg = "Type " ++ show (typeName ti) ++ " does not have named fields"

fieldNames :: (Data a) => a -> [String]
fieldNames x = fieldNamesFromTypeInfo $ typeInfo x

fieldValues :: (Data a) => a -> [String]
fieldValues = gmapQ gshow

fieldValueAsString :: Data a => a -> String -> String
fieldValueAsString x field =
  valueList !! index
  where
    fieldList = fieldNames x
    valueList = fieldValues x
    index = fromMaybe (error $ "Field " ++ field ++ " is not present in type " ++ show (typeName $ typeInfo x)) $ elemIndex field fieldList


-- | Generic show: taken from syb package
gshow :: Data a => a -> String
gshow x = gshows x ""

gshows :: Data a => a -> ShowS
gshows = render `extQ` (shows :: String -> ShowS) where
  render t
    | isTuple = showChar '('
              . drop 1
              . commaSlots
              . showChar ')'
    | isNull = showString "[]"
    | isList = showChar '['
             . drop 1
             . listSlots
             . showChar ']'
    | otherwise = --showChar '('
                constructor
                . slots
                -- . showChar ')'

    where constructor = showString . showConstr . toConstr $ t
          slots = foldr (.) id . gmapQ ((showChar ' ' .) . gshows) $ t
          commaSlots = foldr (.) id . gmapQ ((showChar ',' .) . gshows) $ t
          listSlots = foldr (.) id . init . gmapQ ((showChar ',' .) . gshows) $ t
          isTuple = all (==',') (filter (not . flip elem "()") (constructor ""))
          isNull = all (`elem` "[]") (constructor "")
          isList = constructor "" == "(:)"



-- https://stackoverflow.com/questions/47606189/fromconstrb-or-something-other-useful
applyConstr :: Data a => Constr -> [Dynamic] -> Maybe a
applyConstr ctor args = let
   nextField :: forall d. Data d => StateT [Dynamic] Maybe d
   nextField = do
      as <- get
      case as of
         [] -> lift Nothing  -- too few arguments
         (a:rest) -> do
            put rest
            case fromDynamic a of
               Nothing -> lift Nothing  -- runtime type mismatch
               Just x  -> return x
   in case runStateT (fromConstrM nextField ctor) args of
      Just (x, []) -> Just x
      _            -> Nothing  -- runtime type error or too few / too many arguments

{--
buildFromRecord :: Data a => TypeInfo -> [String] -> Maybe a
buildFromRecord ti record = applyConstr ctor args
  where
    ctor = typeConstructor ti
    argCtors = map fieldConstructor (typeFields ti)
    cvPairs = zip argCtors record
    args = map 
      (\(c, v) -> (fromConstr toConstr (read v)
      cvPairs
 
    args = map (\col -> )
    args = map toDyn record
--}

-- bob = applyConstr (toConstr p) [toDyn (4711 :: Int), toDyn "Bob", toDyn (30 :: Int), toDyn "456 Main St"] :: Maybe Person