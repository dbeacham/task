{-# LANGUAGE OverloadedStrings #-}

module Task where

import System.IO
import Network.AMQP
import qualified Data.ByteString.Lazy.Char8 as BL

main = do
    conn <- openConnection "127.0.0.1" "/" "guest" "guest"
    chan <- openChannel conn

    -- declare a queue, exchange and binding
    declareQueue chan newQueue {queueName = "whoscored-queue"}
    --declareExchange chan newExchange {exchangeName = "myExchange", exchangeType = "direct"}
    bindQueue chan "whoscored-queue" "whoscored" "#"

    publishMsg chan "task" "whoscored.test"
        newMsg {msgBody = (BL.pack "My message"),
                msgDeliveryMode = Just Persistent}

    publishMsg chan "task" "whoscored.test"
        newMsg {msgBody = (BL.pack "My message"),
                msgDeliveryMode = Just Persistent}

    -- confirm-select
    confirmSelect chan False
    addConfirmationListener chan (\(w64, isMult, ackType) ->
      hPutStrLn stderr $
        show ackType ++ ": " ++ (show . fromIntegral $ w64) ++ " (" ++ show isMult ++ ")")

    -- subscribe to the queue
    --consumeMsgs chan "whoscored-queue" Ack myCallback

    -- publish a message to our new exchange
    publishMsg chan "task" "whoscored.test"
        newMsg {msgBody = (BL.pack "My message"),
                msgDeliveryMode = Just Persistent}
    publishMsg chan "task" "whoscored.test"
        newMsg {msgBody = (BL.pack "My message"),
                msgDeliveryMode = Just Persistent}

    confResult <- waitForConfirms chan
    hPutStrLn stderr (show confResult)


    getLine -- wait for keypress
    closeConnection conn
    putStrLn "connection closed"


myCallback :: (Message,Envelope) -> IO ()
myCallback (msg, env) = do
    putStrLn $ "received message: " ++ (BL.unpack $ msgBody msg)
    -- acknowledge receiving the message
    ackEnv env
