import qualified LetLang.Suites  as Let
import qualified ProcLang.Suites as Proc
import           Test.HUnit

main :: IO ()
main = do
  counts <- runTestTT $ TestList
    [ Let.tests
    , Proc.tests
    ]
  return ()
