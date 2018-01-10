{-# LANGUAGE OverloadedStrings #-}
import           Control.Monad    ((>=>))
import           Data.Bits
import qualified Data.ByteString  as B
import           Data.Char        (ord)
import           Data.List        (elemIndex)
import qualified Data.Map.Strict  as M
import           Data.Monoid      (mempty, (<>))
import qualified Data.Text        as T
import           Data.Word        (Word8)
import           Test.Tasty
import           Test.Tasty.HUnit

newtype Base64 = Base64 T.Text deriving (Show, Eq)
newtype HexBytes = HexBytes T.Text deriving (Show, Eq)

hex2bytes :: HexBytes -> Maybe B.ByteString
hex2bytes = hex2bytes' mempty
  where
    hexmap = M.fromList $ zip (['0'..'9'] <> ['a' .. 'f']) [0..]
    hexchar2int x = M.lookup x hexmap

    hex2bytes' :: [Word8] -> HexBytes -> Maybe B.ByteString
    hex2bytes' accum (HexBytes cs)
      | T.length cs == 0 = Just . B.pack . reverse $ accum
      | otherwise = do
          (msb, rest) <- T.uncons cs
          (lsb, rest) <- T.uncons rest
          msb <- hexchar2int msb
          lsb <- hexchar2int lsb

          let byte = fromIntegral $ msb * 16 + lsb

          hex2bytes' (byte:accum) (HexBytes rest)

packBytes :: [Word8] -> Int
packBytes bs =
  foldl (\x (b, i) -> x .|. fromIntegral b `shift` (8 * i)) 0 $
  zip bs (reverse [0 .. length bs - 1])

unpackBits :: Int -> Int -> Int -> [Int]
unpackBits n s x =
  map (\i -> (x .&. mask `shift` (i * s)) `shiftR` (i * s)) $ reverse [0..n-1]
  where
    mask = 2 ^ s - 1

bytes2base64 :: B.ByteString -> Maybe Base64
bytes2base64 bs =
  let padded = B.unpack $ bs <> B.replicate (abs $ B.length bs `mod` (-3)) 0 in
  let chunked = chunksOf 3 padded in

  let encoded = map encodeChunk chunked in

  Base64 . T.concat <$> sequence encoded

  where
    chunksOf :: Int -> [a] -> [[a]]
    chunksOf _ [] = []
    chunksOf n l
      | n > 0 = take n l : chunksOf n (drop n l)
      | otherwise = error "Negative n"

    base64map = M.fromList $
      zip [0..] (['A'..'Z'] <> ['a' .. 'z'] <> ['0'..'9'] <> ['+', '/'])

    encodeChar :: Int -> Maybe Char
    encodeChar n = M.lookup n base64map

    encodeChunk = fmap T.pack . mapM encodeChar . unpackBits 4 6 . packBytes

hex2base64 :: HexBytes -> Maybe Base64
hex2base64 = hex2bytes >=> bytes2base64

main :: IO ()
main = defaultMain $ testGroup "Set 1"
  [ testGroup "Problem 1"
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
  ]
