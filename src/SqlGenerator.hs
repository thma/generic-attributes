module SqlGenerator
  ( --insertStmtFor,
    --updateStmtFor,
    --deleteStmtFor,
    --selectStmtFor,
    selectAllStmtFor,
    preparedInsertStmtFor,
    preparedUpdateStmtFor,
    preparedSelectStmtFor,
    preparedDeleteStmtFor,
    idColumn,
  )
where

import           Data.Char            (toLower)
import           Data.Data            (Data)
import           Data.List            (intercalate)
import           RecordtypeReflection (fieldValueAsString, fieldValuesAsString)
import           TypeInfo             

-- | A function that returns an SQL insert statement for an entity. Type 'a' must be an instance of Data.
-- The function will use the field names of the data type to generate the column names in the insert statement.
-- The values of the fields will be used as the values in the insert statement.
-- Output example: INSERT INTO Person (id, name, age, address) VALUES (123456, "Alice", 25, "123 Main St");
insertStmtFor :: Data a => a -> String
insertStmtFor x =
  "INSERT INTO "
    ++ typeName x
    ++ " ("
    ++ intercalate ", " (fieldNames x)
    ++ ") VALUES ("
    ++ intercalate ", " (fieldValuesAsString x)
    ++ ");"

preparedInsertStmtFor :: Data a => a -> String
preparedInsertStmtFor x =
  "INSERT INTO "
  ++ typeName x
  ++ " ("
  ++ intercalate ", " fNames
  ++ ") VALUES ("
  ++ intercalate ", " params
  ++ ");"
  where
    fNames = fieldNames x
    params = replicate (length fNames) "?"

-- | A function that returns an SQL update statement for an entity. Type 'a' must be an instance of Data.
updateStmtFor :: Data a => a -> String
updateStmtFor x =
  "UPDATE "
    ++ typeName x
    ++ " SET "
    ++ intercalate ", " updatePairs
    ++ " WHERE "
    ++ idColumn ti
    ++ " = "
    ++ fieldValueAsString x (idColumn ti)
    ++ ";"
  where
    updatePairs = zipWith (\n v -> n ++ " = " ++ v) (fieldNames x) (fieldValuesAsString x)
    ti = typeInfo x

preparedUpdateStmtFor :: Data a => a -> String
preparedUpdateStmtFor x =
  "UPDATE "
    ++ typeName x
    ++ " SET "
    ++ intercalate ", " updatePairs
    ++ " WHERE "
    ++ idColumn ti
    ++ " = ?"
    ++ ";"
  where
    fNames = fieldNames x
    updatePairs = map (++ " = ?") fNames
    ti = typeInfo x

-- | A function that returns an SQL select statement for entity type `a` with primary key `id`.
selectStmtFor :: (Show id) => TypeInfo a -> id -> String
selectStmtFor ti eid =
  "SELECT "
    ++ intercalate ", " (fieldNamesFromTypeInfo ti)
    ++ " FROM "
    ++ tiTypeName ti
    ++ " WHERE "
    ++ idColumn ti
    ++ " = "
    ++ show eid
    ++ ";"

preparedSelectStmtFor :: TypeInfo a -> String
preparedSelectStmtFor ti =
  "SELECT "
    ++ intercalate ", " (fieldNamesFromTypeInfo ti)
    ++ " FROM "
    ++ tiTypeName ti
    ++ " WHERE "
    ++ idColumn ti
    ++ " = ?;"

selectAllStmtFor :: TypeInfo a -> String
selectAllStmtFor ti =
  "SELECT "
    ++ intercalate ", " (fieldNamesFromTypeInfo ti)
    ++ " FROM "
    ++ tiTypeName ti
    ++ ";"

deleteStmtFor :: Data a => a -> String
deleteStmtFor x =
  "DELETE FROM "
    ++ show (typeName x)
    ++ " WHERE "
    ++ idColumn ti
    ++ " = "
    ++ fieldValueAsString x (idColumn ti)
    ++ ";"
  where
    ti = typeInfo x

preparedDeleteStmtFor :: Data a => a -> String
preparedDeleteStmtFor x =
  "DELETE FROM "
    ++ show (typeName x)
    ++ " WHERE "
    ++ idColumn ti
    ++ " = ?;"
  where
    ti = typeInfo x

-- "CREATE TABLE IF NOT EXISTS Person (personID INT PRIMARY KEY, name TEXT, age INT, address TEXT);"
{--
createTableStmtFor :: TypeInfo -> String
createTableStmtFor ti =
  "CREATE TABLE IF NOT EXISTS "
    ++ show (typeName ti)
    ++ " ("
    ++ intercalate ", " (zipWith (\n t -> n ++ " " ++ t) (fieldNamesFromTypeInfo ti) (fieldTypesFromTypeInfo ti))
    ++ ");"
--}

-- | A function that returns the name of the primary key column for a type 'a'.
--   By convention we are using the following name: convert the type name to lower case and append "ID".
idColumn :: TypeInfo a -> String
idColumn ti = map toLower (tiTypeName ti) ++ "ID"
