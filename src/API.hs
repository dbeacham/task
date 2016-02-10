{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}

module API where

import Control.Monad (forever)
import Control.Concurrent (forkIO)
import Control.Monad.IO.Class
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BSL
import Servant.API
import Servant.Server
import Data.Proxy
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Data.Aeson
import qualified Database.PostgreSQL.Simple as PG
import Control.Concurrent.Chan
import qualified Network.AMQP as AMQP
  
type CommandAPI
     = "command" :> "createTask":> ReqBody '[JSON] TaskDef :> Post '[JSON] Int
  :<|> "command" :> "pauseTask" :> Capture "TaskId"  Int :> Get '[] ()
  :<|> "command" :> "restartTask" :> Capture "TaskId" Int :> Get '[] ()
  :<|> "command" :> "completeTask" :> Capture "TaskId" Int :> Get '[] ()

commandAPI :: Proxy CommandAPI
commandAPI = Proxy
  
data Priority
  = Batch
  | Important
  deriving (Show, Read, Eq, Ord, Enum)

instance ToJSON Priority where
  toJSON Batch     = String "Batch"
  toJSON Important = String "Important"

instance FromJSON Priority where
  parseJSON = withText "Priority" $ \t ->
    case t of
      "Batch"     -> pure Batch
      "Important" -> pure Important
      other       -> fail $ "Unrecognised priority: " ++ T.unpack other
  
data TaskDef = TaskDef T.Text Value Priority
  deriving (Show)

instance ToJSON TaskDef where
  toJSON (TaskDef action payload priority)
    = object [ "action" .= action
             , "payload" .= payload
             , "priority" .= priority
             ]
  
instance FromJSON TaskDef where
  parseJSON = withObject "TaskDef" $ \o ->
    TaskDef <$> o .: "action"
            <*> o .: "payload"
            <*> o .: "priority"

commandServer :: PG.Connection -> Chan (Int, TaskDef) -> Server CommandAPI
commandServer conn chan = create :<|> pause :<|> restart :<|> complete
  where          
    create taskDef@(TaskDef action payload priority) = do
      [PG.Only taskId] <- liftIO $ PG.query conn "INSERT INTO task (action, payload, priority, published) VALUES (?, ?, ?, false) RETURNING id" (action, payload, fromEnum priority)
      liftIO $ writeChan chan (taskId, taskDef)
      return taskId
    pause x = return ()
    restart x = return ()
    complete x = return ()

app :: PG.Connection -> Chan (Int, TaskDef) -> Application
app conn chan = serve commandAPI (commandServer conn chan)
  
publishTasks :: Chan (Int, TaskDef) -> IO ()
publishTasks pubChan = do
  conn <- AMQP.openConnection "127.0.0.1" "/" "guest" "guest"
  rbChan <- AMQP.openChannel conn

  AMQP.declareExchange rbChan AMQP.newExchange {AMQP.exchangeName = "task.exch.q", AMQP.exchangeType = "topic"}
  AMQP.confirmSelect rbChan True
  AMQP.addConfirmationListener rbChan $ \(w64, b, ack) -> do
    print (fromIntegral w64, b, ack)

  print "Confirm mode"
  
  forever $ do
    (taskId, t@(TaskDef action payload priority)) <- readChan pubChan
    print $ "New task: " ++ show t
    AMQP.publishMsg rbChan "task.exch" action
      AMQP.newMsg { AMQP.msgBody = encode payload
                  , AMQP.msgDeliveryMode = Just AMQP.Persistent
                  }
    print $ "Published"

connInfo = PG.defaultConnectInfo
  { PG.connectHost = "localhost"
  , PG.connectPort = 5432
  , PG.connectDatabase = "trialTask"
  , PG.connectUser = "dbeacham"
  , PG.connectPassword = "dbeacham"
  }

main :: IO ()
main = do
  conn <- PG.connect connInfo
  chan <- newChan
  forkIO (publishTasks chan)
  run 8080 (app conn chan)
