# GenericPersistence - A Haskell Persistence Layer using Generics

[![License BSD3](https://img.shields.io/badge/license-BSD3-brightgreen.svg)](http://opensource.org/licenses/BSD-3-Clause)
[![Actions Status](https://github.com/thma/generic-persistence/workflows/Haskell%20CI/badge.svg)](https://github.com/thma/generic-persistence/actions)
[![codecov](https://codecov.io/gh/thma/generic-persistence/graph/badge.svg?token=DBCFLEA8JZ)](https://codecov.io/gh/thma/generic-persistence)
[![Available on Hackage](https://img.shields.io/hackage/v/generic-persistence.svg?style=flat)](https://hackage.haskell.org/package/generic-persistence)

![GP Logo](https://github.com/thma/generic-persistence/blob/main/gp-logo-300.png?raw=true)



## Table of Contents

- [Introduction](#introduction)
- [Status](#status)
- [Available on Hackage](#available-on-hackage)
- [Short demo](#short-demo)
- [Real world examples](#real-world-examples)
- [Deal with runtime exceptions or use total functions? Your choice!](#deal-with-runtime-exceptions-or-use-total-functions-your-choice)
  - [Exceptions in the default API](#exceptions-in-the-default-api)
  - [Total functions in the safe API](#total-functions-in-the-safe-api)
- [How it works](#how-it-works)
  - [Default Behaviour](#default-behaviour)
  - [Customizing The Default Behaviour](#customizing-the-default-behaviour)
- [Handling enumeration fields](#handling-enumeration-fields)
- [Handling embedded Objects](#handling-embedded-objects)
- [Handling 1:1 references](#handling-11-references)
- [Handling 1:N references](#handling-1n-references)
- [Performing queries with the Query DSL](#performing-queries-with-the-query-dsl)
- [Integrating user defined queries](#integrating-user-defined-queries)
- [The Conn ConnectionContext Type](#the-conn-connection-type)
- [Connection Pooling](#connection-pooling)

## Introduction

GenericPersistence is a small Haskell persistence layer for relational databases. 
The approach relies on [GHC.Generics](https://hackage.haskell.org/package/base-4.17.0.0/docs/GHC-Generics.html). The actual database access is provided by the [HDBC](https://hackage.haskell.org/package/HDBC) library.

The *functional goal* of the persistence layer is to provide hassle-free RDBMS persistence for Haskell data types in 
Record notation (for simplicity I call these *Entities*).

It therefore provides means for inserting, updating, deleting and querying such entities into/from relational databases.

The main *design goal* is to minimize the *boilerplate* code required:

- no manual instantiation of type classes
- no implementation of encoders/decoders
- no special naming convention for types and their attributes 
- no special types to define entities and attributes
- no Template Haskell scaffolding of glue code

In an ideal world we would be able to take any POHO (Plain old Haskell Object) 
and persist it to any RDBMS without any additional effort.

## Status

As of now there is full support for SQLite and PostgreSQL. 
Support for other databases will be implemented on demand.

### new features in v0.6
- Autoincrement flag for primary keys can now defined per Entity
- insert now always returns the inserted entity (thus insertReturning was removed)
- insertMany now also respects handling of primary keys

### new features in v0.5

- support for PostgreSQL
- support RETURNING statement for insert
- support for auto-incrementing primary keys
- entitiesFromRows now available in GP api also
- provide a simple quasi-qoter for defining sql queries
- expose some HDBC functions in the GP API
- explicit setting of transaction mode


Feature requests, feedback and pull requests are welcome!

## Available on Hackage

[https://hackage.haskell.org/package/generic-persistence](https://hackage.haskell.org/package/generic-persistence)

Add the following to your `package.yaml` file:

```yaml
dependencies:
- generic-persistence
```

I would also recommend to add the setting `language: GHC2021`  to your `package.yaml` file:

```yaml
language: GHC2021
```

This drastically reduces the amount of LANGUAGE extensions that need to be added to your source files.


## Short demo

Here now follows a short demo that shows how the library looks and feels from the user's point of view.

```haskell
{-# LANGUAGE DeriveAnyClass #-} -- allows automatic derivation from Entity type class

module Main (main) where

import           Database.GP          
import           Database.HDBC.Sqlite3 (connectSqlite3)
import           GHC.Generics

-- | An Entity data type with several fields, using record syntax.
data Person = Person
  { personID :: Int,
    name     :: String,
    age      :: Int,
    address  :: String
  }
  deriving (Generic, Entity, Show) -- deriving Entity allows us to use the GenericPersistence API


main :: IO ()
main = do
  -- connect to a database in auto commit mode
  conn <- connect AutoCommit <$> connectSqlite3 "sqlite.db"

  -- initialize Person table
  setupTableFor @Person SQLite conn

  alice <- insert conn Person {name = "Alice", age = 25, address = "Elmstreet 1"}
  print alice

  -- update a Person
  update conn alice {address = "Main Street 200"}

  -- select a Person by id
  -- The result type must be provided by the call site,
  -- as `selectById` has a polymorphic return type `IO (Maybe a)`.
  alice' <- selectById @Person conn (personID alice)
  print alice'

  -- select all Persons from a database. again, the result type must be provided.
  allPersons <- select @Person conn allEntries
  print allPersons

  -- select all Persons from a database, where age is smaller 30.
  allPersonsUnder30 <- select @Person conn (field "age" <. (30 :: Int))
  print allPersonsUnder30

  -- delete a Person from a database
  delete conn alice

  -- select all Persons from a database. Now it should be empty.
  allPersons' <- select @Person conn allEntries
  print allPersons'

  -- close connection
  disconnect conn
```

## Real world examples

To learn how to use the library in more complex scenarios, I recommend looking at the following examples:

### Building a REST service with Servant and GenericPersistence

[This example](https://github.com/thma/servant-gp) shows how to use servant to build a REST API that provides CRUD operations for a medium-complex data model.
GenericPersistence is used to execute the CRUD operation against a SQLite database.
A Swagger UI is provided to interact with the API.

### Building a REST service with Scotty and GenericPersistence
[This blog post](https://thma.github.io/posts/2024-12-05-real-worlds-rest-services-with-scotty-and-gp.html)
explains how to use Scotty to build a REST API that provides CRUD operations for a simple data model.
GenericPersistence is used to execute the CRUD operation against a SQLite database.
This example also demonstrate how easy a paging mechanism can be implemented with GenericPersistence.
The code also shows how to use GenericPersistence to manage BearerTokens for validating incoming requests.

### The Elephantine library review

The Elephantine library review provides a good overview of the different libraries available for working with PostgreSQL in Haskell. It evaluates the libraries based on a real world application scenario. This allows to compare the libraries based on the same use cases and see how the libraries differ in their approach.
It also contains a section on *Generic-Persistence*: 
[How to use PostgreSQL with Haskell. Elephantine Library Review 2023](https://github.com/Zelenya/elephants#generic-persistence)

The source code for *the Generic-Persistence based solution* can be found [here](https://github.com/Zelenya/elephants/blob/main/src/Elephants/GenericPersistence.hs).


## Deal with runtime exceptions or use total functions? Your choice!

GenericPersistence provides two different APIs for accessing the database:
- the default API (as shown in the above demo), which uses exceptions to signal errors
- the safe API, which uses `Either` to signal errors

### Exceptions in the default API
The default API is the easiest to use, but you will have to do exception handling to catch runtime errors. To use it you'll have to import the `Database.GP` module:

```haskell
import Database.GP 
```

These are the exceptions that can be thrown:

```haskell
data PersistenceException =
    EntityNotFound String
  | DuplicateInsert String
  | DatabaseError String
  | NoUniqueKey String
  deriving (Show, Eq, Exception)
```

The `EntityNotFound` exception is thrown when you try to select an entity by its primary key, but no entity with the given primary key exists in the database.

The `DuplicateInsert` exception is thrown when you try to insert an entity into the database, but an entity with the same primary key already exists in the database.

The `DatabaseError` exception is thrown when the database backend returns an error.

The `NoUniqueKey` exception is thrown when you try to select an entity by its primary key, but multiple rows are returned by the database. This can happen if there is no primary key constraint defined on the underlying database column.

A real world example can be found in the [Servant GP - UserServer](https://github.com/thma/servant-gp/blob/main/src/UserServer.hs) module.

### Total functions in the safe API

The safe API is a bit more verbose, but it does not throw exceptions. To use it you'll have to import the `Database.GP.GenericPersistenceSafe` module:

```haskell
import Database.GP.GenericPersistenceSafe
```

This module provides the same function as `Database.GP`, but all functions return `Either PersistenceException a` instead of `IO a` or `IO (Maybe a)`.

```haskell
eitherExRes <- selectById conn "1" :: IO (Either PersistenceException Person)
case eitherExRes of
  Left (EntityNotFound _) -> print "Entity not found"
  Right person            -> print person
```

This may look a bit verbose, but in actual code this may work out better, as `Either` allows pattern matching and chaining of computations with the `do` notation.

A real world example can be found in the [Servant GP - UserServerSafe](https://github.com/thma/servant-gp/blob/main/src/UserServerSafe.hs) module. The `UserServerSafe` module is a copy of the `UserServer` module, but it uses the safe API instead of the default API. As you can see, the code of `UserServerSafe` is actually a bit more compact than the code of UserServer. (In the default API, we have to deal with the special case of `selectById` returning `Nothing`.)

## How it works

In order to store Haskell data types in a relational database, we need to define a mapping between Haskell types and database tables.
This mapping is defined by the `Entity` type class. This type class comes with default implementations for all methods which define 
the standard behaviour. (The default implementations internally use `GHC.Generics`.)

This default mapping will work for many cases, but it can be customized by overriding the default implementations.

### The Entity type class

The `Entity` type class specifies the following methods:

```haskell
class (Generic a, HasConstructor (Rep a), HasSelectors (Rep a)) => Entity a where
  -- | Converts a database row to a value of type 'a'.
  fromRow :: Conn -> [SqlValue] -> IO a

  -- | Converts a value of type 'a' to a database row.
  toRow :: Conn -> a -> IO [SqlValue]

  -- | Returns the name of the primary key field for a type 'a'.
  idField :: String

  -- | Returns a list of tuples that map field names to column names for a type 'a'.
  fieldsToColumns :: [(String, String)]

  -- | Returns the name of the table for a type 'a'.
  tableName :: String

  -- | Returns True if the primary key field for a type 'a' is autoincremented by the database.
  autoIncrement :: Bool
```

### Default Behaviour

`idField`, `fieldsToColumns` and `tableName` are used to define the mapping between Haskell types and database tables.

- The default implementations of `idField` returns a default value for the field name of the primary key field of a type `a`:
The type name in lower case, plus "ID".
E.g. `idField @Book` will return `"bookID"`.

- `tableName` returns the name of the database table used for type `a`. The default implementation simply returns the constructor name of `a`. E.g. `tableName @Book` will return `"Book"`.

- `fieldsToColumns` returns a list of tuples that map field names of type `a` to database column names for a type. The default implementation simply returns a list of tuples that map the field names of `a` to the field names of `a`. E.g. `fieldsToColumns @Person` will return `[("personID","personID"),("name","name"),("age","age"),("address","address")]`.

- `autoIncrement` returns `True` by default. This means that the primary key field of a type `a` is assumed to be autoincremented by the database. If this is not the case, you can override the default implementation to return `False`.

`fromRow` and `toRow` are used to convert between Haskell types and database rows. 

- `fromRow` converts a database row, represented by a `[SqlValue]` to a value of type `a`. 

- `toRow` converts a value of type `a` to a `[SqlValue]`, representing a database row. 

The default implementations of `fromRow` and `toRow` expects that type `a` has a single constructor and a selector for each field. All fields are expected to have a 1:1 mapping to a column in the database table.
Thus each field must have a type that can be converted to and from a `SqlValue`. 

For example 

```haskell
toRow conn (Person {personID = 1234, name = "Alice", age = 27, address = "Elmstreet 1"}) 
````

will return 

```haskell
[SqlInt64 1234,SqlString "Alice",SqlInt64 27,SqlString "Elmstreet 1"]
```

And `fromRow` does the inverse: 
```haskell
fromRow conn [SqlInt64 1234,SqlString "Alice",SqlInt64 27,SqlString "Elmstreet 1"] :: IO Person
``` 

returns 

```haskell
Person {personID = 1234, name = "Alice", age = 27, address = "Elmstreet 1"}
```

The conversion functions `toRow` and `fromRow` both carry an additional `Conn` argument. This argument is not used by the default implementations, but it can be used to provide database access during the conversion process. We will cover this later.

### Customizing the default behaviour

The default implementations of `idField`, `fieldsToColumns`, `tableName`, `fromRow` and `toRow` can be customized by overriding the default implementations.
Overiding `idField`, `fieldsToColumns` and `tableName` will be required when your database tables do not follow the default naming conventions.

For example, if we have a database table `BOOK_TBL` with the following columns:

```sql
CREATE TABLE BOOK_TBL 
  ( bookId INTEGER PRIMARY KEY, 
    bookTitle TEXT, 
    bookAuthor TEXT, 
    bookYear INTEGER
  );
```
and we want to map this table to a Haskell data type `Book`:

```haskell
data Book = Book
  { book_id :: Int,
    title   :: String,
    author  :: String,
    year    :: Int
  }
  deriving (Generic, Show)
```

Then we can customize the default implementations of `idField`, `fieldsToColumns` and `tableName` to achieve the desired mapping:

```haskell
instance Entity Book where
  -- this is the primary key field of the Book data type (not following the default naming convention)
  idField = "book_id"

  -- this defines the mapping between the field names of the Book data type and the column names of the database table
  fieldsToColumns = [("book_id", "bookId"), ("title", "bookTitle"), ("author", "bookAuthor"), ("year", "bookYear")]

  -- this is the name of the database table
  tableName = "BOOK_TBL"
```

Overriding `fromRow` and `toRow` will be required when your database tables do not follow the default mapping conventions.
We will see some examples in later sections.

## Handling enumeration fields

Say we have a data type `Book` with an enumeration field of type `BookCategory`:

```haskell
data Book = Book
  { bookID :: Int,
    title   :: String,
    author  :: String,
    year    :: Int,
    category :: BookCategory
  }
  deriving (Generic, Entity, Show)

data BookCategory = Fiction | Travel | Arts | Science | History | Biography | Other
  deriving (Generic, Show, Enum)
```

In this case everything works out of the box, because *GenericPersistence* provides `Convertible` instances for all `Enum` types. `Convertible` instances are used to convert between Haskell types and database types.

If you do not want to use `Enum` types for your enumeration fields, you have to implement `Convertible` instances manually:

```haskell
data BookCategory = Fiction | Travel | Arts | Science | History | Biography | Other
  deriving (Generic, Show, Read)

instance Convertible BookCategory SqlValue where
  safeConvert = Right . toSql . show
  
instance Convertible SqlValue BookCategory where
  safeConvert = Right . read . fromSql  
```

## Handling embedded Objects

Say we have a data type `Article` with a field of type `Author`:

```haskell
data Article = Article
  { articleID :: Int,
    title     :: String,
    author    :: Author,
    year      :: Int
  }
  deriving (Generic, Show, Eq)

data Author = Author
  { authorID :: Int,
    name     :: String,
    address  :: String
  }
  deriving (Generic, Show, Eq)  
```

If we don't want to store the `Author` as a separate table, we can use the following approach to embed the `Author` into the `Article` table:

```haskell
instance Entity Article where
  -- in the fields to column mapping we specify that all fields of the 
  -- Author type are also mapped to columns of the Article table:
  fieldsToColumns :: [(String, String)]
  fieldsToColumns = [("articleID", "articleID"),
                       ("title", "title"), 
                       ("authorID", "authorID"), 
                       ("authorName", "authorName"), 
                       ("authorAddress", "authorAddress"),
                       ("year", "year")
                    ]

  -- in fromRow we have to manually construct the Author object from the 
  -- respective columns of the Article table and insert it 
  -- into the Article object:
  fromRow _conn row = return $ Article (col 0) (col 1) author (col 5)
    where
      col i = fromSql (row !! i)
      author = Author (col 2) (col 3) (col 4)

  -- in toRow we have to manually extract the fields of the Author object
  -- and insert them into the respective columns of the Article table:
  toRow _conn a = return [toSql (articleID a), toSql (title a), toSql authID, toSql authorName, toSql authorAddress, toSql (year a)]
    where 
      authID = authorID (author a)
      authorName = name (author a)
      authorAddress = address (author a)
```

## Handling 1:1 references

If we have the same data types as in the previous example, but we want to store the `Author` in a separate table, we can use the following approach:

```haskell
data Article = Article
  { articleID :: Int,
    title     :: String,
    author    :: Author,
    year      :: Int
  }
  deriving (Generic, Show, Eq)

data Author = Author
  { authorID :: Int,
    name     :: String,
    address  :: String
  }
  deriving (Generic, Entity, Show, Eq)


instance Entity Article where
  fieldsToColumns :: [(String, String)]                      -- ommitting the author field,
  fieldsToColumns =                                          -- as this can not be mapped to a single column
    [ ("articleID", "articleID"),                            -- instead we invent a new column authorID         
      ("title", "title"),
      ("authorID", "authorID"),
      ("year", "year")
    ]

  fromRow :: Conn -> [SqlValue] -> IO Article
  fromRow conn row = do    
    authorById <- fromJust <$> selectById conn (row !! 2)  -- load author by foreign key
    return $ rawArticle {author = authorById}              -- add author to article
    where
      rawArticle = Article (col 0) (col 1)                 -- create article from row, 
                           (Author (col 2) "" "") (col 3)  -- using a dummy author
        where
          col i = fromSql (row !! i)

  toRow :: Conn -> Article -> IO [SqlValue]
  toRow conn a = do
    upsert conn (author a)                                  -- persist author first
    return [toSql (articleID a), toSql (title a),           -- return row for article table where 
            toSql $ authorID (author a), toSql (year a)]    -- authorID is foreign key to author table 
```

Persisting the `Author`as a side effect in `toRow` may sound like an *interesting* idea...
This step is optional. But then the user has to make sure that the `Author` is persisted before the `Article` is persisted.


## Handling 1:n references

Now let's change the previous example by having a list of Articles in the `Author` type:

```haskell
data Author = Author
  { authorID :: Int,
    name     :: String,
    address  :: String,
    articles :: [Article]
  }
  deriving (Generic, Show, Eq)

data Article = Article
  { articleID :: Int,
    title     :: String,
    authorId  :: Int,
    year      :: Int
  }
  deriving (Generic, Entity, Show, Eq)
```

So now we have a `1:n` relationship between `Author` and `Article`. 

We can handle this situation by using the following instance declaration for `Author`:

```haskell
instance Entity Author where
  fieldsToColumns :: [(String, String)]                   -- ommitting the articles field, 
  fieldsToColumns =                                       -- as this can not be mapped to a single column
    [ ("authorID", "authorID"),
      ("name", "name"),
      ("address", "address")
    ]

  fromRow :: Conn -> [SqlValue] -> IO Author
  fromRow conn row = do
    let authID = head row                                  -- authorID is the first column
    articlesBy <- select conn (field "authorId" =. authID) -- retrieve all articles by this author
    return rawAuthor {articles = articlesBy}               -- add the articles to the author
    where
      rawAuthor = Author (col 0) (col 1) (col 2) []        -- create the author from row (w/o articles)
      col i = fromSql (row !! i)                           -- helper function to convert SqlValue to Haskell type

  toRow :: Conn -> Author -> IO [SqlValue]
  toRow conn a = do
    mapM_ (upsert conn) (articles a)                      -- persist all articles of this author (update or insert)
    return [toSql (authorID a),                           -- return the author as a list of SqlValues
            toSql (name a), toSql (address a)]
```

Persisting all articles of an author as a side effect during the conversion of the author to a row may seem *special*...
You can ommit this step. But then you have to persist the articles manually before persisting the author.

## Performing queries with the Query DSL

The library provides a simple DSL for performing `SELECT`queries. The `select` function 

```haskell
select :: forall a. (Entity a) => Conn -> WhereClauseExpr -> IO [a]
```

This function retrieves all entities of type `a` that match some query criteria.
The function takes an HDBC connection (wrapped in a `Conn`) and a `WhereClauseExpr` as parameters.
The function returns a (possibly empty) list of all matching entities.

The `WhereClauseExpr` is constructed using a small set of functions and infix operators.

There are a set of infix operators `(=.), (>.), (<.), (>=.), (<=.), (<>.), like, between, in', contains` that define field comparisons:

```haskell
field "name" =. "John"

field "age" >=. 18

field "age" `between` (18, 30)

field "name" `like` "J%"

field "name" `in'` ["John", "Jane"]
```

Then we have three function `isNull`, `allEntries` and `byId` that also define simple `WHERE` clauses:

```haskell
isNull (field "name") -- matches all entries where the name field is NULL

byId 42               -- matches the entry where the primary key column has the value 42

allEntries            -- matches all entries of the table
```

It is also possible to apply SQL functions to fields:

```haskell
lower = sqlFun "LOWER" -- define a function that applies the SQL function LOWER to a field

lower(field "name") =. "all lowercase"
```

These field-wise comparisons can be combined using the logical operators `&&.`, `||.` and `not'`:

```haskell
(field "name" `like` "J%") &&. (field "age" >=. 18)

(field "name" =. "John") ||. (field "name" =. "Jane")

not' (field "name" =. "John")
```

The `select` function will then use the `WhereClauseExpr` constructed from these operators and functions to generate a SQL query that retrieves all matching entities:

```haskell

ageField :: Field
ageField = field "age"

thirtySomethings <- select @Person conn (ageField `between` (30, 39))
```

It is also possible to add `ORDER BY` and `LIMIT` clauses to the query:

```haskell
sortedPersons <- select @Person conn (allEntries `orderBy` [(ageField,ASC), (nameField,DESC)])

limitedPersons <- select @Person conn (allEntries `limit` 25)

pageOfPersons <- select @Person conn (allEntries `limitOffset` (100,10))
```

You will find more examples in the [test suite](https://github.com/thma/generic-persistence/blob/main/test/QuerySpec.hs).


## Integrating user defined queries

As we have seen in the previous section, the library provides two functions `select` and `selectById` to query the database for entities.

If you want to use more complex queries, you can integrate HDBC SQL queries by using the `entitiesFromRows` function as in the following example:

```haskell
main :: IO ()
main = do
  -- connect to a database
  conn <- connect SQLite <$> connectSqlite3 ":memory:" 

  -- initialize Person table
  setupTableFor @Person conn

  let alice = Person 1 "Alice" 25 "123 Main St"
      bob = Person 2 "Bob" 30 "456 Elm St"
      charlie = Person 3 "Charlie" 35 "789 Pine St"
      dave = Person 4 "Dave" 40 "1011 Oak St"
      eve = Person 5 "Eve" 45 "1213 Maple St"
      frank = Person 6 "Frank" 50 "1415 Walnut St"
      people = [alice, bob, charlie, dave, eve, frank]
      
  -- insert all persons into the database
  insertMany conn people

  -- perform a custom query with HDBC
  stmt = "SELECT * FROM Person WHERE age >= ? ORDER BY age ASC"
  resultRows <- quickQuery conn stmt [toSql (40 :: Int)]

  -- convert the resulting rows into a list of Person objects
  fourtplussers <- entitiesFromRows @Person conn resultRows
  print fourtplussers
```

Of course this approach is not type safe. It is up to the user to make sure that the query returns the correct columns. 

## The `Conn` Connection Type

The `Conn` type is a wrapper around an `IConnection` obtained from an HDBC backend driver like `HDBC-sqlite3` or `hdbc-postgresql`. It is used to pass the connection to the database to *Generic-Persistence*. All functions of the library that require a database connection take a `Conn` as an argument.

HDBC provides a very similar type called `ConnectionWrapper`. The main reason for such a wrapper type is to simplify the type signatures of the library functions. 

In addition, the `Conn` type provides additional database related information that is not available in the `ConnectionWrapper` type. For example, the `Conn` type contains the name of the database driver that is used. This information can be used to generate the correct SQL statements for different database backends.
`Conn` also carries a flag that indicates whether implicit commits should be used by the library. This flag is set to `True` by default. If you want to use explicit commits, you can set the flag to `False` by modifying the `Conn` value:
  
```haskell
c <- connect SQLite <$> connectSqlite3 ":memory:"
let conn = c {implicitCommit = False}
```

## Connection Pooling

The library provides a simple connection pool for managing database connections. 
This is a must in multi-threaded environments where multiple threads may need to access the database at the same time. A typical use case is a REST service that uses a database to store its data. 

The connection Pool is implemented based on the [resource-pool](https://hackage.haskell.org/package/resource-pool) library. `generic-persistence` exposes a `ConnectionPool` type and two function `createConnPool` and `withResource` to create and use a connection pool.

The following example shows how to create a connection pool and how to use it to perform a database query:

```haskell

sqlLitePool :: FilePath -> IO ConnectionPool
sqlLitePool sqlLiteFile = createConnPool SQLite sqlLiteFile connectSqlite3 10 100

main :: IO ()
main = do
  connPool <- sqlLitePool ":memory:" 
  let alice = Person 123456 "Alice" 25 "123 Main St"
  withResource connPool $ \conn -> do
    setupTableFor @Person conn
    insert conn alice
    allPersons <- select conn allEntries :: IO [Person]
    print allPersons
```

You'll find a more complete example in the [servant-gp repo](https://github.com/thma/servant-gp/blob/main/src/ServerUtils.hs#L45).
There I have set up a sample REST service based on Servant that uses *Generic-Persistence* and a connection pool to manage the database connections.


