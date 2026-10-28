module Main (main) where

import Kenshou.Cli (mainWith, selfTestAssembly)

main :: IO ()
main = mainWith selfTestAssembly
