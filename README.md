# Writing a Haskell persistence layer using Generics and Reflection

## Introduction

In this article I'll describe how to write a rudimentary Haskell persistence layer (on top of HDBC). 
My approach will rely heavily on Generics (`Data.Data`, `Data.Typeable`) and Reflection (`Type.Reflection`).

<!--
Some twenty years back the Java community became increasingly unhappy with the persistence mechanism provided by SUN, 
the Entity Beans of the Enterprise Java Beans (EJB) framework. The EJB framework required developers to implement 
complex interfaces and to write a lot of boilerplate code to integrate into the heavy machinery of the EJB-container.

Developers wanted to have persistence features for their [plain old Java objects* 
(POJOs)](https://en.wikipedia.org/wiki/Plain_old_Java_object) without all the boilerplate and dependencies on awkward frameworks.
-->

The *functional goal* of my persistence layer is to provide hassle-free RDBMS persistence for Haskell data types in 
Record notation (for brevity I call them *Entities*).

That is, it must provide means for inserting, updating, deleting and quering such enties to/from relational databases.

Not in scope for the current state of the library are things like:
- A query language
- User-definable mappings of Haskell types to RDBMS types
- Handling of relationships between entities (1:1, 1:n, n:m)
- Handling of transactions
- Handling of database migrations
- Handling of database schemas
- Handling of database connections and sessions
- Handling auto-incrementing primary keys
- Caching
- ...

So as of now it's just about the bare minimum to get some data into a database and to get it back out again.

The main *design goal* is to minimize the *boilerplate* code required. Ideally I would like to achieve the following:

- no manual instantiation of type classes
- no implementation of encoders/decoders
- no special naming convention for types and their attributes 
- no special types to define entities and attributes
- no Template Haskell scaffolding of glue code

In an ideal world we would be able to take any POHO (Plain old Haskell Object) 
and persist it to any RDBMS without any additional effort.

## Short demo

Here now follows a short demo that shows how the library looks and feels from the user's point of view.

```haskell
{-# LANGUAGE DeriveDataTypeable#-}
module Main (main) where

import Data.Data ( Data )
import TypeInfo ( typeInfo ) 
import GenericPersistence( deleteEntity, persistEntity, retrieveAllEntities, retrieveEntityById )
import Database.HDBC (disconnect, runRaw, commit) 
import Database.HDBC.Sqlite3 ( connectSqlite3 )

-- | define a data type with several fields, using record syntax.
data Person = Person
  { personID :: Int
  , name :: String
  , age :: Int
  , address :: String
  } deriving (Data)
```

The persistent data type must be deriving the `Data.Data` type class. This is required
to enable all the Generics magics to work behind the scenes. 
Fortunately, deriving `Data` needs no manual implementation, we get it for free by enabling `DeriveDataTypeable`.

```haskell
main :: IO ()
main = do
    -- initialize Person table
    conn <- connectSqlite3 "sqlite.db"
    runRaw conn "DROP TABLE IF EXISTS Person;"
    runRaw conn "CREATE TABLE IF NOT EXISTS Person (personID INT PRIMARY KEY, name TEXT, age INT, address TEXT);"
    commit conn
```

As of now my library does not cover the creation of database tables. So this is still a manual step.
As already mentioned, the library does not cover any user defined mapping of data type attributes to columns.
As of now the same names for the attributes and the columns are used.
For the column types we are choosing types that can be automatically converted by HDBC. 

Now we move on to using the actual library functions:

```haskell
    -- create a Person entity
    let alice = Person {personID = 123456, name = "Alice", age = 25, address = "Elmstreet 1"}

    -- insert a Person into a database
    persist conn alice

    -- update a Person
    persist conn alice {address = "Main Street 200"}  
    
    -- select a Person from a database
    -- The result type must be provided explicitly, as `retrieveById` has a polymorphic return type `IO a`.
    alice' <- retrieveById conn "123456" :: IO Person

    -- delete a Person from a database
    delete conn alice'
    
    -- close connection
    disconnect conn
```

And here comes the output of the demo program. As you can see, there is some trace output for each of the database operations.

```haskell
ghci> main
Inserting Person 123456 "Alice" 25 "Elmstreet 1"
Updating Person 123456 "Alice" 25 "Main Street 200"
Retrieve Person with id 123456
Deleting Person with id 123456
```

Summarizing, we can state that there is virtually no boilerplate code required in the user code.
The only thing we have to do is to derive the `Data` type class for our persistent data types.
The library takes care of the rest.

I' explicitely asking for feedback here:
- Do you regard such a persistence API as useful?
- Do you have any suggestions for improvements?
- Do you think it makes sense to continue working on it, or are there already enough libraries out there that do the same?

## A deeper dive into the library

In this section we are taking a closer look at the library internals. Let's start with the `persist` function:

```haskell
-- | A function that persists an entity to a database.
-- The function takes an HDBC connection and an entity (fulfilling constraint 'Data a') as parameters.
-- The entity is either inserted or updated, depending on whether it already exists in the database.
-- The required SQL statements are generated dynamically using Haskell generics and reflection
persist :: (IConnection conn, Data a) => conn -> a -> IO ()
persist conn entity = do
  resultRows <- quickQuery conn selectStmt []
  case resultRows of
    [] -> do
      trace $ "Inserting " ++ gshow entity
      runRaw conn insertStmt
      commit conn
    [_singleRow] -> do
      trace $ "Updating " ++ gshow entity
      runRaw conn updateStmt
      commit conn
    _ -> error $ "More than one entity found for id " ++ show eid
  where
    ti = typeInfo entity
    eid = entityId entity
    selectStmt = selectStmtFor ti eid
    insertStmt = insertStmtFor entity
    updateStmt = updateStmtFor entity

entityId :: forall d. (Data d) => d -> String
entityId x = fieldValueAsString x (idColumn (typeInfo x))

trace :: String -> IO ()
trace = putStrLn
```

The overall logic of this function is as follows:

1. Perform a select query against the table corresponding to type `a` to check whether a record is already present for the primary key value derived from `entity`.
2. If the list of resulting rows is empty, the entity has not been persisted before and an `INSERT`-statement has to be excecuted.
3. If the list contains exactly one row, the entity already was stored in the DB and an `UPDATE`-statement has to be executed.
4. If the list contains more than one row, something is wrong and an error is thrown.

The `selectStmtFor`, `insertStmtFor` and `updateStmtFor` functions are used to generate the required SQL statements dynamically.

Let's start with `insertStmtFor` as it is the simplest one.

Let's say we have a Person entity:

```haskell
alice :: Person
alice = Person {personID = 123456, name = "Alice", age = 25, address = "Elmstreet 1"}
```

Then the corresponding insert statement is:

```sql
INSERT INTO Person (id, name, age, address) VALUES (123456, "Alice", 25, "Elmstreet 1");
```

So in order to generate the insert statement we need to know the table name, the column names and the values.
The idea is to use Haskell Generics to obtain these from the entity instance.
As of now I'm using the type- and attribute-names directly as column names. But this could be easily changed later on.
The tricky business is to dynamically inspect the entity instance and extract the values of the attributes.

So here comes the code for `insertStmtFor`:

```haskell
import           TypeInfo             (TypeInfo, fieldNames,
                                       fieldNamesFromTypeInfo, fieldValues,
                                       typeInfo, typeName, tiTypeName)

insertStmtFor :: Data a => a -> String
insertStmtFor x =
  "INSERT INTO "
    ++ typeName x
    ++ " ("
    ++ intercalate ", " (fieldNames x)
    ++ ") VALUES ("
    ++ intercalate ", " (fieldValues x)
    ++ ");"
```

The overall construction of the insert statement is obvious. We just need to know a bit more about the `typeName`, `fieldNames` and `fieldValues` functions from the `TypeInfo` module:

```haskell
typeName :: (Data a) => a -> String
typeName = show . toConstr 
```