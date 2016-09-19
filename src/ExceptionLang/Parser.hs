module ExceptionLang.Parser
( expression
, program
, parseProgram
) where

import           Control.Monad          (void)
import           Data.Maybe             (fromMaybe)
import           ExceptionLang.Data
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

lexeme :: Parser a -> Parser a
lexeme = L.lexeme spaceConsumer

keyWord :: String -> Parser ()
keyWord w = string w *> notFollowedBy alphaNumChar *> spaceConsumer

reservedWords :: [String]
reservedWords  =
  [ "let", "in", "if", "then", "else", "zero?", "minus"
  , "equal?", "greater?", "less?", "proc", "letrec"
  , "try", "catch", "raise"
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
                then fail $
                  concat ["keyword ", show x, " cannot be an identifier"]
                else return x

integer :: Parser Integer
integer = lexeme L.integer

signedInteger :: Parser Integer
signedInteger = L.signed spaceConsumer integer

-- expressionPair ::= (Expression, Expression)
expressionPair :: Parser (Expression, Expression)
expressionPair = parens $ do
  expr1 <- expression
  _ <- comma
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
  _ <- keyWord "if"
  ifE <- expression
  _ <- keyWord "then"
  thenE <- expression
  _ <- keyWord "else"
  elseE <- expression
  return $ IfExpr ifE thenE elseE

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
  _ <- keyWord letType
  bindings <- many binding
  _ <- keyWord "in"
  body <- expression
  return $ builder bindings body
  where
    binding = try $ do
      var <- identifier
      _ <- equal
      val <- expression
      return (var, val)

-- | LetrecExpr ::= letrec {Identifier (Identifier) = Expression} in Expression
letRecExpr :: Parser Expression
letRecExpr = do
  _ <- keyWord "letrec"
  procBindings <- many procBinding
  _ <- keyWord "in"
  recBody <- expression
  return $ LetRecExpr procBindings recBody
  where
    procBinding = try $ do
      procName <- identifier
      params <- parens (sepBy identifier comma)
      _ <- equal
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

-- | ProcExpr ::= proc ({Identifier}*) Expression
procExpr :: Parser Expression
procExpr = do
  _ <- keyWord "proc"
  params <- parens . many $ identifier
  body <- expression
  return $ ProcExpr params body

-- | CallExpr ::= (Expression {Expression}*)
callExpr :: Parser Expression
callExpr = parens $ do
  rator <- expression
  rand <- many expression
  return $ CallExpr rator rand

-- | TryExpr ::= try Expression catch (Identifier) Expression
tryExpr :: Parser Expression
tryExpr = do
  _ <- keyWord "try"
  body <- expression
  _ <- keyWord "catch"
  exception <- parens identifier
  handler <- expression
  return $ TryExpr body exception handler

-- | RaiseExpr ::= raise Expression
raiseExpr :: Parser Expression
raiseExpr = do
  _ <- keyWord "raise"
  RaiseExpr <$> expression

-- | Expression ::= ConstExpr
--              ::= BinOpExpr
--              ::= UnaryOpExpr
--              ::= IfExpr
--              ::= VarExpr
--              ::= LetExpr
--              ::= ProcExpr
--              ::= CallExpr
--              ::= TryExpr
--              ::= LetRecExpr
--              ::= RaiseExpr
expression :: Parser Expression
expression = foldl1 (<|>) (fmap try expressionList)
  where
    expressionList =
      [ constExpr
      , binOpExpr
      , unaryOpExpr
      , ifExpr
      , varExpr
      , letExpr
      , procExpr
      , callExpr
      , letRecExpr
      , tryExpr
      , raiseExpr
      ]

program :: Parser Program
program = do
  _ <- spaceConsumer
  expr <- expression
  _ <- eof
  return $ Prog expr
