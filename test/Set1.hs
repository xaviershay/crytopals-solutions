{-# LANGUAGE OverloadedStrings #-}

module Set1 where

import qualified Data.ByteString.Lazy    as B
import Data.List (sortOn, transpose, genericLength)
import           Data.Maybe (fromJust, catMaybes)
import           Data.Monoid        ((<>))
import qualified Data.Text.Lazy          as T

import           Test.Tasty
import           Test.Tasty.HUnit


import Lib

test_Set_1_Challenge_1 = testGroup "Challenge 1"
  [ testCase "simple hex2bytes" $
    (Just . B.pack $ [0, 255]) @=? hex2bytes (HexBytes "00ff")
  , testCase "simple bytes2base64" $
    Just (Base64 "AAAA") @=? bytes2base64 (B.pack [0])
  , testCase "invalid hex char"   $ Nothing @=? hex2base64 (HexBytes "ZZ")
  , testCase "invalid hex length" $ Nothing @=? hex2base64 (HexBytes "F")
  , testCase "given" $
    Just (Base64 $ "SSdtIGtpbGxpbmcgeW91ciBicmFpbiB" <>
                   "saWtlIGEgcG9pc29ub3VzIG11c2hyb29t") @=?
    hex2base64
      (HexBytes $ "49276d206b696c6c696e6720796f757220627261696e2" <>
                  "06c696b65206120706f69736f6e6f7573206d757368726f6f6d")
  ]

unit_Set_1_Challenge_2 =
    fromHexString "746865206b696420646f6e277420706c6179" @=?
      fromHexString "1c0111001f010100061a024b53535009181c" `xorBytes`
      fromHexString "686974207468652062756c6c277320657965"

unit_Set_1_Challenge_3 = Just "Cooking MC's like a pound of bacon" @=? f
      (fromHexString $ "1b37373331363f78151b7f2b783431333d7839782" <>
                       "8372d363c78373e783a393b3736")

  where
    -- The input cypher is known to xor'ed with a single character. Try decoding
    -- against all characters, using a simple heuristic to determine which output
    -- looks most "english like".
    f :: B.ByteString -> Maybe T.Text
    f bs =
      let candidateKeys  = generateSingleCharKeys bs in
      let candidateTexts = map (xorBytes bs) candidateKeys in

      -- head is safe here because it is operating on the list constructed with a
      -- constant range above
      chooseMostLikelyText candidateTexts

unit_Set_1_Challenge_4 = do
  cipherTexts <- lines <$> readFile "data/4.txt"

  Just "Now that the party is jumping\n" @=? f cipherTexts

  where
    f :: [String] -> Maybe T.Text
    f ss =
      let candidateInputs = map (fromHexString . T.pack) ss in
      let candidateTexts =
            [ xorBytes x y
               | x <- candidateInputs
               , y <- generateSingleCharKeys x
            ] in

        chooseMostLikelyText candidateTexts

unit_Set_1_Challenge_5 =
  (fromHexString $ "0b3637272a2b2e63622c2e69692a23693a2a3c6324202d623" <>
                   "d63343c2a26226324272765272a282b2f20430a652e2c652a" <>
                   "3124333a653e2b2027630c692b20283165286326302e27282f")
    @=?
      xorBytes "ICE"
        ("Burning 'em, if you ain't quick and nimble\n" <>
        "I go crazy when I hear a cymbal")

unit_hamming_distance =
  37 @=? hammingDistance "this is a test" "wokka wokka!!!"

focus = unit_Set_1_Challenge_6

unit_Set_1_Challenge_6 = do
  cipherText <- concat . lines <$> readFile "data/6.txt"

  Just "Terminator X: Bring the noise" @=?
    solveKey (Base64 . T.pack $ cipherText)

  where
    -- The input cypher is encrypted with repeating key XOR, then base64
    -- encoded.
    solveKey :: Base64 -> Maybe B.ByteString
    solveKey s =
      -- This is an arbitrary range. In theory the key could be any length, but
      -- if it's too long there won't be enough information for each byte of
      -- the key for this method of analysis to work.
      let possibleKeySizes = [2..40] in

      -- Limit analysis to 3 most promising candidates to reduce time spent. A
      -- perhaps better approach would be to define a score "threshold" and
      -- take the first text that exceeds it.
      let scoredKeySizes = take 3 . sortOn scoreKeySize $ possibleKeySizes in

      let possibleKeys = catMaybes . map bestKeyForKeySize $ scoredKeySizes in

      -- Zip together keys and texts so that we can use either for our return
      -- value.
      let possibleTexts = zip possibleKeys $
                          map (xorBytes bytes) possibleKeys in

      case sortOn (negate . score . snd) possibleTexts of
        [] -> Nothing
        ((k, _):_) -> Just k

      where
        bytes = fromJust . base642bytes $ s

        -- Take the first arbitrary handful of blocks for the given keysize,
        -- and calculate how close they are. Smaller distance means more likely
        -- that this is the correct key size.
        scoreKeySize :: Int -> Double
        scoreKeySize n =
          let n64 = fromIntegral n in
          let blocks = map (\i -> B.take n64 . B.drop (n64 * i) $ bytes) [0..3] in
          let distances = map (fromIntegral . uncurry hammingDistance) $
                          zip blocks (tail blocks) in

          sum distances / genericLength distances / (fromIntegral n)

        -- Given a key size, for each potential character in that key extract
        -- the bytes that would have been encoded with it and test them against
        -- every possible key. The one with the highest score heuristic is
        -- selected as the best. In theory, the nth best could also be valid,
        -- but we ignore that case here.
        bestKeyForKeySize :: Int -> Maybe B.ByteString
        bestKeyForKeySize keysize =
          let blocks = map B.pack . transpose $ chunksOf keysize (B.unpack bytes) in
          let keys = map chooseMostLikelyKey blocks in

          case sequence keys of
            Nothing -> Nothing
            Just x -> Just $ B.pack (map B.head x)

        chooseMostLikelyKey :: B.ByteString -> Maybe B.ByteString
        chooseMostLikelyKey bs =
          let candidateKeys = generateSingleCharKeys bs in
          let candidates = sortOn (negate . score . xorBytes bs) candidateKeys in

          case candidates of
            [] -> Nothing
            (x:_) -> Just x