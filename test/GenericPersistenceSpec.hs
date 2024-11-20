{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -Wno-deprecations #-}
{-# OPTIONS_GHC -Wno-missing-fields #-}

module GenericPersistenceSpec
  ( test,
    spec,
  )
where

import           Control.Exception
import           Database.GP.GenericPersistence
import           Database.HDBC
import           Database.HDBC.Sqlite3
import           GHC.Generics                   hiding (Selector)
import           Test.Hspec

-- `test` is here so that this module can be run from GHCi on its own.  It is
-- not needed for automatic spec discovery.
-- (start up stack repl --test to bring up ghci and have access to all the test functions)
test :: IO ()
test = hspec spec

prepareDB :: IO Conn
prepareDB = do
  conn <- connect AutoCommit <$> connectSqlite3 ":memory:"
  setupTable @Person conn defaultSqliteMapping
  setupTable @Book conn defaultSqliteMapping
  setupTable @Car conn defaultSqliteMapping
  return conn

-- | A data type with several fields, using record syntax.
data Person = Person
  { personID :: Int,
    name     :: String,
    age      :: Int,
    address  :: String
  }
  deriving (Generic, Show, Eq)

instance Entity Person where
  autoIncrement = False

data Car = Car
  { carID   :: Int,
    carType :: String
  }
  deriving (Generic, Show, Eq)

instance Entity Car where
  autoIncrement = True
  idField = "carID"

data Book = Book
  { book_id  :: Int,
    title    :: String,
    author   :: String,
    year     :: Int,
    category :: BookCategory
  }
  deriving (Generic, Show, Eq)

data BookCategory = Fiction | Travel | Arts | Science | History | Biography | Other
  deriving (Generic, Read, Show, Eq, Enum)

instance Entity Book where
  idField = "book_id"
  fieldsToColumns =
    [ ("book_id", "bookId"),
      ("title", "bookTitle"),
      ("author", "bookAuthor"),
      ("year", "bookYear"),
      ("category", "bookCategory")
    ]
  tableName = "BOOK_TBL"
  fromRow _c row = pure $ Book (col 0) (col 1) (col 2) (col 3) (col 4)
    where
      col i = fromSql (row !! i)

  toRow _c b = pure [toSql (book_id b), toSql (title b), toSql (author b), toSql (year b), toSql (category b)]

person :: Person
person = Person 123456 "Alice" 25 "123 Main St"

manyPersons :: [Person]
manyPersons =
  [ Person 1 "Alice" 25 "123 Main St",
    Person 2 "Bob" 30 "456 Elm St",
    Person 3 "Charlie" 35 "789 Pine St",
    Person 4 "Dave" 40 "1011 Oak St",
    Person 5 "Eve" 45 "1213 Maple St",
    Person 6 "Frank" 50 "1415 Walnut St"
  ]

book :: Book
book = Book 1 "The Hobbit" "J.R.R. Tolkien" 1937 Fiction

spec :: Spec
spec = do
  describe "GenericPersistence" $ do
    it "retrieves Entities using Generics" $ do
      conn <- prepareDB
      let bob = Person 1 "Bob" 36 "7 West Street"
      runRaw conn "INSERT INTO Person (personID, name, age, address) VALUES (1, \"Bob\", 36, \"7 West Street\");"
      runRaw conn "INSERT INTO Person (personID, name, age, address) VALUES (2, \"Alice\", 25, \"7 West Street\");"
      runRaw conn "INSERT INTO Person (personID, name, age, address) VALUES (3, \"Frank\", 56, \"7 West Street\");"
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 3
      head allPersons `shouldBe` bob
      person' <- selectById conn (1 :: Int) :: IO (Maybe Person)
      person' `shouldBe` Just bob
    it "retrieves the number of selected Entities" $ do
      conn <- prepareDB
      insertMany conn manyPersons
      countPersons <- count @Person conn allEntries
      countPersons `shouldBe` 6
    it "selectById returns Nothing if no Entity was found" $ do
      conn <- prepareDB
      person' <- selectById conn (1 :: Int) :: IO (Maybe Person)
      person' `shouldBe` Nothing
    it "selectById throws a DatabaseError if things go wrong in the DB" $ do
      conn <- connect AutoCommit <$> connectSqlite3 ":memory:"
      eitherEA <- try (selectById conn (1 :: Int) :: IO (Maybe Person))
      case eitherEA of
        Left (DatabaseError msg) -> msg `shouldContain` "no such table: Person"
        Left _                   -> expectationFailure "Expected DatabaseError"
        Right _                  -> expectationFailure "Expected DatabaseError"
    it "retrieves Entities using user implementation" $ do
      conn <- prepareDB
      let hobbit = Book 1 "The Hobbit" "J.R.R. Tolkien" 1937 Fiction
      runRaw conn "INSERT INTO BOOK_TBL (bookId, bookTitle, bookAuthor, bookYear, bookCategory) VALUES (1, \"The Hobbit\", \"J.R.R. Tolkien\", 1937, 0);"
      runRaw conn "INSERT INTO BOOK_TBL (bookId, bookTitle, bookAuthor, bookYear, bookCategory) VALUES (2, \"The Lord of the Rings\", \"J.R.R. Tolkien\", 1955, 0);"
      runRaw conn "INSERT INTO BOOK_TBL (bookId, bookTitle, bookAuthor, bookYear, bookCategory) VALUES (3, \"Smith of Wootton Major\", \"J.R.R. Tolkien\", 1967, 0);"
      allBooks <- select conn allEntries :: IO [Book]
      length allBooks `shouldBe` 3
      head allBooks `shouldBe` hobbit
      book' <- selectById conn (1 :: Int) :: IO (Maybe Book)
      book' `shouldBe` Just hobbit
    it "select returns Nothing if no Entity was found" $ do
      conn <- prepareDB
      allPersons' <- select @Person conn allEntries
      allPersons' `shouldBe` []
    it "select throws a DatabaseError if things go wrong" $ do
      conn <- connect AutoCommit <$> connectSqlite3 ":memory:"
      eitherEA <- try (select @Person conn allEntries)
      case eitherEA of
        Left (DatabaseError msg) -> msg `shouldContain` "no such table: Person"
        Left _                   -> expectationFailure "Expected DatabaseError"
        Right _                  -> expectationFailure "Expected DatabaseError"
    it "can materialize Entities from user defined SQL queries" $ do
      conn <- prepareDB
      insertMany conn manyPersons
      let stmt =
            [sql|
                    SELECT *
                    FROM Person
                    WHERE age >= ?
                    ORDER BY age ASC
                    |]
      resultRows <- quickQuery conn stmt [toSql (40 :: Int)]
      allPersons <- entitiesFromRows @Person conn resultRows
      length allPersons `shouldBe` 3
    it "persists new Entities using Generics" $ do
      conn <- prepareDB
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 0
      persist conn person
      allPersons' <- select conn allEntries :: IO [Person]
      length allPersons' `shouldBe` 1
      person' <- selectById conn (123456 :: Int) :: IO (Maybe Person)
      person' `shouldBe` Just person
    it "persists new Entities using user implementation" $ do
      conn <- prepareDB
      allbooks <- select conn allEntries :: IO [Book]
      length allbooks `shouldBe` 0
      persist conn book
      allbooks' <- select conn allEntries :: IO [Book]
      length allbooks' `shouldBe` 1
      book' <- selectById conn (1 :: Int) :: IO (Maybe Book)
      book' `shouldBe` Just book
    it "persist throws an exception if things go wrong" $ do
      conn <- connect AutoCommit <$> connectSqlite3 ":memory:"
      eitherEA <- try (persist conn book)
      case eitherEA of
        Left (DatabaseError msg) -> msg `shouldContain` "no such table: BOOK_TBL"
        Left _ -> expectationFailure "Expected DatabaseError"
        Right _ -> expectationFailure "Expected DatabaseError"
    it "persists existing Entities using Generics" $ do
      conn <- prepareDB
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 0
      persist conn person
      allPersons' <- select conn allEntries :: IO [Person]
      length allPersons' `shouldBe` 1
      persist conn person {age = 26}
      person' <- selectById conn (123456 :: Int) :: IO (Maybe Person)
      person' `shouldBe` Just person {age = 26}
    it "persists existing Entities using user implementation" $ do
      conn <- prepareDB
      allbooks <- select conn allEntries :: IO [Book]
      length allbooks `shouldBe` 0
      persist conn book
      allbooks' <- select conn allEntries :: IO [Book]
      length allbooks' `shouldBe` 1
      eitherEA <- try $ persist conn book {year = 1938} :: IO (Either PersistenceException ())
      case eitherEA of
        Left _  -> expectationFailure "should not throw an exception"
        Right x -> x `shouldBe` ()
      book' <- selectById conn (1 :: Int) :: IO (Maybe Book)
      book' `shouldBe` Just book {year = 1938}
    it "inserts Entities using Generics" $ do
      conn <- prepareDB
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 0
      _ <- insert conn person
      allPersons' <- select conn allEntries :: IO [Person]
      length allPersons' `shouldBe` 1
      person' <- selectById conn (123456 :: Int) :: IO (Maybe Person)
      person' `shouldBe` Just person
    it "inserts Entities with autoincrement handling" $ do
      conn <- prepareDB
      myCar@(Car carId _) <- insert conn Car {carType = "Honda Jazz"}
      myCar' <- selectById conn carId :: IO (Maybe Car)
      myCar' `shouldBe` Just myCar
    it "inserts many Entities re-using a single prepared stmt" $ do
      conn <- prepareDB
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 0
      insertMany conn manyPersons
      allPersons' <- select conn allEntries :: IO [Person]
      length allPersons' `shouldBe` 6
    it "inserts many alsodoes autoincrement handling" $ do
      conn <- prepareDB
      insertMany conn [Car {carType = "Honda Jazz"}]
      [Car carId typ] <- select @Car conn allEntries
      typ `shouldBe` "Honda Jazz"
      carId `shouldBe` 1
    it "updates many Entities re-using a single prepared stmt" $ do
      conn <- prepareDB
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 0
      insertMany conn manyPersons
      allPersons' <- select conn allEntries :: IO [Person]
      length allPersons' `shouldBe` 6
      let manyPersons' = map (\p -> p {name = "Bob"}) manyPersons
      updateMany conn manyPersons'
      allPersons'' <- select conn allEntries :: IO [Person]
      all (\p -> name p == "Bob") allPersons'' `shouldBe` True
    it "deletes many Entities re-using a single prepared stmt" $ do
      conn <- prepareDB
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 0
      insertMany conn manyPersons
      allPersons' <- select conn allEntries :: IO [Person]
      length allPersons' `shouldBe` 6
      deleteMany conn allPersons'
      allPersons'' <- select conn allEntries :: IO [Person]
      length allPersons'' `shouldBe` 0

    it "inserts Entities using user implementation" $ do
      conn <- prepareDB
      allbooks <- select conn allEntries :: IO [Book]
      length allbooks `shouldBe` 0
      _ <- insert conn book
      allbooks' <- select conn allEntries :: IO [Book]
      length allbooks' `shouldBe` 1
      book' <- selectById conn (1 :: Int) :: IO (Maybe Book)
      book' `shouldBe` Just book
    it "updates Entities using Generics" $ do
      conn <- prepareDB
      _ <- insert conn person
      update conn person {name = "Bob"}
      person' <- selectById conn (123456 :: Int) :: IO (Maybe Person)
      person' `shouldBe` Just person {name = "Bob"}
    it "updates Entities using user implementation" $ do
      conn <- prepareDB
      _ <- insert conn book
      update conn book {title = "The Lord of the Rings"}
      book' <- selectById conn (1 :: Int) :: IO (Maybe Book)
      book' `shouldBe` Just book {title = "The Lord of the Rings"}
    it "deletes Entities using Generics" $ do
      conn <- prepareDB
      _ <- insert conn person
      allPersons <- select conn allEntries :: IO [Person]
      length allPersons `shouldBe` 1
      delete conn person
      allPersons' <- select conn allEntries :: IO [Person]
      length allPersons' `shouldBe` 0
    it "deletes Entities using user implementation" $ do
      conn <- prepareDB
      _ <- insert conn book
      allBooks <- select conn allEntries :: IO [Book]
      length allBooks `shouldBe` 1
      delete conn book
      allBooks' <- select conn allEntries :: IO [Book]
      length allBooks' `shouldBe` 0
    it "provides a Connection Pool" $ do
      connPool <- sqlLitePool ":memory:"
      withResource connPool $ \conn -> do
        setupTable @Person conn defaultSqliteMapping
        _ <- insert conn person
        allPersons <- select conn allEntries :: IO [Person]
        length allPersons `shouldBe` 1

sqlLitePool :: FilePath -> IO ConnectionPool
sqlLitePool sqlLiteFile = createConnPool AutoCommit sqlLiteFile connectSqlite3 10 100
