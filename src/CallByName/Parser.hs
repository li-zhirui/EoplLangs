module CallByName.Parser
( expression
, program
, parseProgram
) where

import           CallByName.Data
import           Control.Monad          (void)
import           Data.Maybe             (fromMaybe)
import           Text.Megaparsec
import           Text.Megaparsec.Expr
import qualified Text.Megaparsec.Lexer  as L
import           Text.Megaparsec.String

parseProgram :: String -> Try Program
parseProgram input = case runParser program "Program Parser" input of
  Left err -> Left $ show err
  Right p  -> Right p

spaceConsumer :: Parser ()
spaceConsumer = L.space (void spaceChar) lineCmnt blockCmnt
  where lineCmnt  = L.skipLineComment "//"
        blockCmnt = L.skipBlockComment "/*" "*/"

symbol = L.symbol spaceConsumer

parens = between (symbol "(") (symbol ")")
minus = symbol "-"
equal = symbol "="
comma = symbol ","
longArrow = symbol "==>"
semiColon = symbol ";"

lexeme :: Parser a -> Parser a
lexeme = L.lexeme spaceConsumer

keyWord :: String -> Parser ()
keyWord w = string w *> notFollowedBy alphaNumChar *> spaceConsumer

reservedWords :: [String]
reservedWords  =
  [ "let", "in", "if", "then", "else", "zero?", "minus"
  , "equal?", "greater?", "less?", "cond", "end", "proc", "letrec"
  , "begin", "set"
  ]

binOpsMap :: [(String, BinOp)]
binOpsMap =
  [ ("+", Add), ("-", Sub), ("*", Mul), ("/", Div), ("equal?", Eq)
  , ("greater?", Gt), ("less?", Le) ]

binOp :: Parser BinOp
binOp = do
  opStr <- foldl1 (<|>) (fmap (try . symbol . fst) binOpsMap)
  return $ fromMaybe
    (error ("Unknown operator '" `mappend` opStr `mappend` "'"))
    (lookup opStr binOpsMap)

unaryOpsMap :: [(String, UnaryOp)]
unaryOpsMap =
  [ ("minus", Minus), ("zero?", IsZero) ]

unaryOp :: Parser UnaryOp
unaryOp = do
  opStr <- foldl1 (<|>) (fmap (try . symbol . fst) unaryOpsMap)
  return $ fromMaybe
    (error ("Unknown operator '" `mappend` opStr `mappend` "'"))
    (lookup opStr unaryOpsMap)

-- | Identifier ::= String (without reserved words)
identifier :: Parser String
identifier = lexeme (p >>= check)
  where
    p       = (:) <$> letterChar <*> many alphaNumChar
    check x = if x `elem` reservedWords
                then fail $ concat
                  ["keyword ",  show x, " cannot be an identifier"]
                else return x

integer :: Parser Integer
integer = lexeme L.integer

signedInteger :: Parser Integer
signedInteger = L.signed spaceConsumer integer

-- expressionPair ::= (Expression, Expression)
expressionPair :: Parser (Expression, Expression)
expressionPair = parens $ do
  expr1 <- expression
  comma
  expr2 <- expression
  return (expr1, expr2)

-- | ConstExpr ::= Number
constExpr :: Parser Expression
constExpr = ConstExpr . ExprNum <$> signedInteger

-- | BinOpExpr ::= BinOp (Expression, Expression)
binOpExpr :: Parser Expression
binOpExpr = do
  op <- binOp
  exprPair <- expressionPair
  return $ uncurry (BinOpExpr op) exprPair

-- | UnaryOpExpr ::= UnaryOp (Expression)
unaryOpExpr :: Parser Expression
unaryOpExpr = do
  op <- unaryOp
  expr <- parens expression
  return $ UnaryOpExpr op expr

-- | IfExpr ::= if Expression then Expression
ifExpr :: Parser Expression
ifExpr = do
  keyWord "if"
  ifE <- expression
  keyWord "then"
  thenE <- expression
  keyWord "else"
  elseE <- expression
  return $ CondExpr [(ifE, thenE), (ConstExpr (ExprBool True), elseE)]

-- | VarExpr ::= Identifier
varExpr :: Parser Expression
varExpr = VarExpr <$> identifier

-- | LetExpr ::= let {Identifier = Expression}* in Expression
letExpr :: Parser Expression
letExpr = letFamilyExpr "let" LetExpr

letFamilyExpr :: String
              ->  ([(String, Expression)] -> Expression -> Expression)
              -> Parser Expression
letFamilyExpr letType builder = do
  keyWord letType
  bindings <- many binding
  keyWord "in"
  body <- expression
  return $ builder bindings body
  where
    binding = try assignment

-- | LetrecExpr ::= letrec {Identifier (Identifier) = Expression} in Expression
letRecExpr :: Parser Expression
letRecExpr = do
  keyWord "letrec"
  procBindings <- many procBinding
  keyWord "in"
  recBody <- expression
  return $ LetRecExpr procBindings recBody
  where
    procBinding = try $ do
      procName <- identifier
      params <- parens $ many identifier
      equal
      procBody <- expression
      return (procName, params, procBody)


-- | ManyExprs ::= <empty>
--             ::= Many1Exprs
manyExprs :: Parser [Expression]
manyExprs = sepBy expression comma

-- | Many1Exprs ::= Expression
--              ::= Expression , Many1Exprs
many1Exprs :: Parser [Expression]
many1Exprs = sepBy1 expression comma

-- | CondExpr ::= cond {Expression ==> Expression}* end
condExpr :: Parser Expression
condExpr = do
  keyWord "cond"
  pairs <- many pair
  keyWord "end"
  return $ CondExpr pairs
  where
    pair = try $ do
      expr1 <- expression
      longArrow
      expr2 <- expression
      return (expr1, expr2)

-- | ProcExpr ::= proc ({Identifier}*) Expression
procExpr :: Parser Expression
procExpr = do
  keyWord "proc"
  params <- parens $ many identifier
  body <- expression
  return $ ProcExpr params body

-- | CallExpr ::= (Expression {Expression}*)
callExpr :: Parser Expression
callExpr = parens $ do
  rator <- expression
  rands <- many expression
  return $ CallExpr rator rands

-- | BeginExpr ::= begin BeginBody end
--
--   BeginBody ::= <empty>
--             ::= Expression BeginBodyTail
--
--   BeginBodyTail ::= <empty>
--                 ::= ; Expression BeginBodyTail
beginExpr :: Parser Expression
beginExpr = do
  keyWord "begin"
  exprs <- sepBy1 (try expression) semiColon
  keyWord "end"
  return $ BeginExpr exprs

assignment :: Parser (String, Expression)
assignment = do
  name <- identifier
  equal
  expr <- expression
  return (name, expr)

-- | AssignExpr ::= set Identifier = Expression
assignExpr :: Parser Expression
assignExpr = do
  keyWord "set"
  assign <- assignment
  return $ uncurry AssignExpr assign

-- | Expression ::= ConstExpr
--              ::= BinOpExpr
--              ::= UnaryOpExpr
--              ::= IfExpr
--              ::= CondExpr
--              ::= VarExpr
--              ::= LetExpr
--              ::= ProcExpr
--              ::= CallExpr
--              ::= LetRecExpr
--              ::= BeginExpr
--              ::= AssignExpr
expression :: Parser Expression
expression = foldl1 (<|>) (fmap try expressionList)
  where
    expressionList =
      [ constExpr
      , binOpExpr
      , unaryOpExpr
      , ifExpr
      , condExpr
      , varExpr
      , letExpr
      , procExpr
      , callExpr
      , letRecExpr
      , beginExpr
      , assignExpr
      ]

program :: Parser Program
program = do
  spaceConsumer
  expr <- expression
  eof
  return $ Prog expr
