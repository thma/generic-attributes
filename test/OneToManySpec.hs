-- allows automatic derivation from Entity type class
{-# LANGUAGE DeriveAnyClass #-}

module OneToManySpec
  ( test,
    spec,
  )
where

import           Data.Maybe                     (fromJust)
import           Database.GP.GenericPersistence
import           Database.HDBC
import           Database.HDBC.Sqlite3
import           GHC.Generics
import           Test.Hspec

-- `test` is here so that this module can be run from GHCi on its own.  It is
-- not needed for automatic spec discovery. (start up stack repl --test to bring up ghci and have access to all the test functions)
test :: IO ()
test = hspec spec

prepareDB :: IO Conn
prepareDB = do
  conn <- Conn SQLite <$> connectSqlite3 ":memory:"
  _ <- setupTableFor conn :: IO Article
  _ <- setupTableFor conn :: IO Author
  return conn

data Article = Article
  { articleID :: Int,
    title     :: String,
    authorId  :: Int,
    year      :: Int
  }
  deriving (Generic, Entity, Show, Eq) -- automatically derives Entity

data Author = Author
  { authorID :: Int,
    name     :: String,
    address  :: String,
    articles :: [Article]
  }
  deriving (Generic, Show, Eq)

instance Entity Author where
  fieldsToColumns :: [(String, String)]
  fieldsToColumns =
    [ ("authorID", "authorID"),
      ("name", "name"),
      ("address", "address")
    ]

  fromRow :: Conn -> [SqlValue] -> IO Author
  fromRow conn row = do
    authID <- idValue conn rawAuthor
    articlesByAuth <- retrieveAllWhere conn "authorId" authID
    return rawAuthor {articles = articlesByAuth}
    where
      rawAuthor = Author (col 0) (col 1) (col 2) []
      col i = fromSql (row !! i)

  toRow :: Conn -> Author -> IO [SqlValue]
  toRow conn a = do
    mapM_ (persist conn) (articles a)
    return [toSql (authorID a), toSql (name a), toSql (address a)]


article1 :: Article
article1 =
  Article
    { articleID = 1,
      title = "Persistence without Boilerplate",
      authorId = 1,
      year = 2018
    }

article2 :: Article
article2 =
  Article
    { articleID = 2,
      title = "Boilerplate for Dummies",
      authorId = 2,
      year = 2020
    }

article3 :: Article
article3 =
  Article
    { articleID = 3,
      title = "The return of the boilerplate",
      authorId = 2,
      year = 2022
    }

arthur :: Author
arthur =
  Author
    { authorID = 2,
      name = "Arthur Miller",
      address = "Denver",
      articles = [article2, article3]
    }

spec :: Spec
spec = do
  describe "Handling of 1:N References" $ do
    it "works like a charm" $ do
      conn <- prepareDB

      insert conn arthur
      insert conn article1

      authors <- retrieveAll conn :: IO [Author]
      length authors `shouldBe` 1

      articles' <- retrieveAll conn :: IO [Article]
      length articles' `shouldBe` 3

      author2 <- retrieveById conn "2" :: IO (Maybe Author)
      fromJust author2 `shouldBe` arthur
      length (articles $ fromJust author2) `shouldBe` 2
