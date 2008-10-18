module Tests
where
import qualified Data.Map as Map
import Text.ParserCombinators.Parsec
import Test.HUnit
import Ledger
import Utils
import Options
import BalanceCommand
import PrintCommand
import RegisterCommand


runtests args = do
  putStrLn $ printf "Running %d tests%s ..\n" n s
  runTestTT flattests
      where
        tests = [unittests, functests]
        deeptests = tfilter matchname $ TestList tests
        flattests = TestList $ filter matchname $ concatMap tflatten tests
        matchname = Tests.matchpats args . tname
        n = length ts where (TestList ts) = flattests
        s | null args = ""
          | otherwise = printf " matching %s" 
                        (intercalate ", " $ map (printf "\"%s\"") args)

matchpats pats str = (null positives || any match positives) && (null negatives || not (any match negatives))
    where
      (negatives,positives) = partition isnegative pats
      isnegative = (== [Ledger.negativepatternchar]) . take 1
      match "" = True
      match pat = containsRegex (mkRegexWithOpts pat' True True) str
          where 
            pat' = if isnegative pat then drop 1 pat else pat

-- | Get a Test's label, or the empty string.
tname :: Test -> String
tname (TestLabel n _) = n
tname _ = ""

-- | Flatten a Test containing TestLists into a list of single tests.
tflatten :: Test -> [Test]
tflatten (TestLabel _ t@(TestList _)) = tflatten t
tflatten (TestList ts) = concatMap tflatten ts
tflatten t = [t]

-- | Filter any TestLists in a Test, recursively, preserving the structure.
tfilter :: (Test -> Bool) -> Test -> Test
tfilter p (TestList ts) = TestList $ filter (any p . tflatten) $ map (tfilter p) ts
tfilter p (TestLabel l t) = TestLabel l (tfilter p t)
tfilter _ t = t

------------------------------------------------------------------------------

unittests = TestList [
  -- remember to indent assertequal arguments, contrary to haskell-mode auto-indent
  "show dollars" ~: show (dollars 1) ~?= "$1.00"
  ,
  "show hours" ~: show (hours 1) ~?= "1.0h"
  ,
  "amount arithmetic"   ~: do
    let a1 = dollars 1.23
    let a2 = Amount (comm "$") (-1.23)
    let a3 = Amount (comm "$") (-1.23)
    assertequal (Amount (comm "$") 0) (a1 + a2)
    assertequal (Amount (comm "$") 0) (a1 + a3)
    assertequal (Amount (comm "$") (-2.46)) (a2 + a3)
    assertequal (Amount (comm "$") (-2.46)) (a3 + a3)
    assertequal (Amount (comm "$") (-2.46)) (sum [a2,a3])
    assertequal (Amount (comm "$") (-2.46)) (sum [a3,a3])
    assertequal (Amount (comm "$") 0) (sum [a1,a2,a3,-a3])
  ,
  "ledgertransaction"  ~: do
    assertparseequal rawtransaction1 (parsewith ledgertransaction rawtransaction1_str)
  ,                  
  "ledgerentry"        ~: do
    assertparseequal entry1 (parsewith ledgerentry entry1_str)
  ,
  "autofillEntry"      ~: do
    assertequal
      (dollars (-47.18))
      (tamount $ last $ etransactions $ autofillEntry entry1)
  ,
  "punctuatethousands"      ~: punctuatethousands "" @?= ""
  ,
  "punctuatethousands"      ~: punctuatethousands "1234567.8901" @?= "1,234,567.8901"
  ,
  "punctuatethousands"      ~: punctuatethousands "-100" @?= "-100"
  ,
  "expandAccountNames" ~: do
    assertequal
      ["assets","assets:cash","assets:checking","expenses","expenses:vacation"]
      (expandAccountNames ["assets:cash","assets:checking","expenses:vacation"])
  ,
  "ledgerAccountNames" ~: do
    assertequal
      ["assets","assets:cash","assets:checking","assets:saving","equity","equity:opening balances",
       "expenses","expenses:food","expenses:food:dining","expenses:phone","expenses:vacation",
       "liabilities","liabilities:credit cards","liabilities:credit cards:discover"]
      (accountnames ledger7)
  ,
  "cacheLedger"        ~: do
    assertequal 15 (length $ Map.keys $ accountmap $ cacheLedger rawledger7)
  ,
  "transactionamount"       ~: do
    assertparseequal (dollars 47.18) (parsewith transactionamount " $47.18")
    assertparseequal (Amount (Commodity {symbol="$",side=L,spaced=False,comma=False,precision=0,rate=1}) 1) (parsewith transactionamount " $1.")
  ]

------------------------------------------------------------------------------

functests = TestList [
  balancecommandtests
  ,registercommandtests
  ]

balancecommandtests = TestList [
  "simple balance report" ~: do
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                 $-1  assets\n\
     \                  $2  expenses\n\
     \                 $-2  income\n\
     \                  $1  liabilities\n\
     \" --"
     (showBalanceReport [] [] l)
 ,
  "balance report with showsubs" ~: do
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                 $-1  assets\n\
     \                 $-2    cash\n\
     \                  $1    saving\n\
     \                  $2  expenses\n\
     \                  $1    food\n\
     \                  $1    supplies\n\
     \                 $-2  income\n\
     \                 $-1    gifts\n\
     \                 $-1    salary\n\
     \                  $1  liabilities:debts\n\
     \" --"
     (showBalanceReport [ShowSubs] [] l)
 ,
  "balance report with account pattern o" ~: do
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                  $1  expenses:food\n\
     \                 $-2  income\n\
     \--------------------\n\
     \                 $-1\n\
     \" --"
     (showBalanceReport [] ["o"] l)
 ,
  "balance report with account pattern o and showsubs" ~: do
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                  $1  expenses:food\n\
     \                 $-2  income\n\
     \                 $-1    gifts\n\
     \                 $-1    salary\n\
     \--------------------\n\
     \                 $-1\n\
     \" --"
     (showBalanceReport [ShowSubs] ["o"] l)
 ,
  "balance report with account pattern a" ~: do
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                 $-1  assets\n\
     \                 $-2    cash\n\
     \                  $1    saving\n\
     \                 $-1  income:salary\n\
     \                  $1  liabilities\n\
     \--------------------\n\
     \                 $-1\n\
     \" --"
     (showBalanceReport [] ["a"] l)
 ,
  "balance report with account pattern e" ~: do
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                 $-1  assets\n\
     \                  $2  expenses\n\
     \                  $1    supplies\n\
     \                 $-2  income\n\
     \                  $1  liabilities:debts\n\
     \" --"
     (showBalanceReport [] ["e"] l)
 ,
  "balance report with unmatched parent of two matched subaccounts" ~: 
  do
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                 $-2  assets:cash\n\
     \                  $1  assets:saving\n\
     \--------------------\n\
     \                 $-1\n\
     \" --"
     (showBalanceReport [] ["cash","saving"] l)
 ,
  "balance report with multi-part account name" ~: 
  do 
    l <- ledgerfromfile "sample.ledger"
    assertequal
     "                  $1  expenses:food\n\
     \--------------------\n\
     \                  $1\n\
     \" --"
     $ showBalanceReport [] ["expenses:food"] l
 ,
  "balance report negative account pattern always matches full name" ~: 
  do 
    l <- ledgerfromfile "sample.ledger"
    assertequal "" $ showBalanceReport [] ["-e"] l
 ]

registercommandtests = TestList [
  "register does something" ~:
  do 
    l <- ledgerfromfile "sample.ledger"
    assertnotequal "" $ showRegisterReport [] [] l
  ]
  
-- | Assert a parsed thing equals some expected thing, or print a parse error.
assertparseequal :: (Show a, Eq a) => a -> (Either ParseError a) -> Assertion
assertparseequal expected parsed = either printParseError (assertequal expected) parsed

------------------------------------------------------------------------------
-- data

rawtransaction1_str  = "  expenses:food:dining  $10.00\n"

rawtransaction1 = RawTransaction "expenses:food:dining" (dollars 10) "" RegularTransaction

entry1_str = "\
\2007/01/28 coopportunity\n\
\  expenses:food:groceries                 $47.18\n\
\  assets:checking\n\
\\n" --"

entry1 =
    (Entry "2007/01/28" False "" "coopportunity" ""
     [RawTransaction "expenses:food:groceries" (dollars 47.18) "" RegularTransaction, 
      RawTransaction "assets:checking" (dollars (-47.18)) "" RegularTransaction] "")


entry2_str = "\
\2007/01/27 * joes diner\n\
\  expenses:food:dining                    $10.00\n\
\  expenses:gifts                          $10.00\n\
\  assets:checking                        $-20.00\n\
\\n" --"

entry3_str = "\
\2007/01/01 * opening balance\n\
\    assets:cash                                $4.82\n\
\    equity:opening balances\n\
\\n\
\2007/01/01 * opening balance\n\
\    assets:cash                                $4.82\n\
\    equity:opening balances\n\
\\n\
\2007/01/28 coopportunity\n\
\  expenses:food:groceries                 $47.18\n\
\  assets:checking\n\
\\n" --"

periodic_entry1_str = "\
\~ monthly from 2007/2/2\n\
\  assets:saving            $200.00\n\
\  assets:checking\n\
\\n" --"

periodic_entry2_str = "\
\~ monthly from 2007/2/2\n\
\  assets:saving            $200.00         ;auto savings\n\
\  assets:checking\n\
\\n" --"

periodic_entry3_str = "\
\~ monthly from 2007/01/01\n\
\    assets:cash                                $4.82\n\
\    equity:opening balances\n\
\\n\
\~ monthly from 2007/01/01\n\
\    assets:cash                                $4.82\n\
\    equity:opening balances\n\
\\n" --"

ledger1_str = "\
\\n\
\2007/01/27 * joes diner\n\
\  expenses:food:dining                    $10.00\n\
\  expenses:gifts                          $10.00\n\
\  assets:checking                        $-20.00\n\
\\n\
\\n\
\2007/01/28 coopportunity\n\
\  expenses:food:groceries                 $47.18\n\
\  assets:checking                        $-47.18\n\
\\n\
\" --"

ledger2_str = "\
\;comment\n\
\2007/01/27 * joes diner\n\
\  expenses:food:dining                    $10.00\n\
\  assets:checking                        $-47.18\n\
\\n" --"

ledger3_str = "\
\2007/01/27 * joes diner\n\
\  expenses:food:dining                    $10.00\n\
\;intra-entry comment\n\
\  assets:checking                        $-47.18\n\
\\n" --"

ledger4_str = "\
\!include \"somefile\"\n\
\2007/01/27 * joes diner\n\
\  expenses:food:dining                    $10.00\n\
\  assets:checking                        $-47.18\n\
\\n" --"

ledger5_str = ""

ledger6_str = "\
\~ monthly from 2007/1/21\n\
\    expenses:entertainment  $16.23        ;netflix\n\
\    assets:checking\n\
\\n\
\; 2007/01/01 * opening balance\n\
\;     assets:saving                            $200.04\n\
\;     equity:opening balances                         \n\
\\n" --"

ledger7_str = "\
\2007/01/01 * opening balance\n\
\    assets:cash                                $4.82\n\
\    equity:opening balances                         \n\
\\n\
\2007/01/01 * opening balance\n\
\    income:interest                                $-4.82\n\
\    equity:opening balances                         \n\
\\n\
\2007/01/02 * ayres suites\n\
\    expenses:vacation                        $179.92\n\
\    assets:checking                                 \n\
\\n\
\2007/01/02 * auto transfer to savings\n\
\    assets:saving                            $200.00\n\
\    assets:checking                                 \n\
\\n\
\2007/01/03 * poquito mas\n\
\    expenses:food:dining                       $4.82\n\
\    assets:cash                                     \n\
\\n\
\2007/01/03 * verizon\n\
\    expenses:phone                            $95.11\n\
\    assets:checking                                 \n\
\\n\
\2007/01/03 * discover\n\
\    liabilities:credit cards:discover         $80.00\n\
\    assets:checking                                 \n\
\\n\
\2007/01/04 * blue cross\n\
\    expenses:health:insurance                 $90.00\n\
\    assets:checking                                 \n\
\\n\
\2007/01/05 * village market liquor\n\
\    expenses:food:dining                       $6.48\n\
\    assets:checking                                 \n\
\\n" --"

rawledger7 = RawLedger
          [] 
          [] 
          [
           Entry {
             edate="2007/01/01", 
             estatus=False, 
             ecode="*", 
             edescription="opening balance", 
             ecomment="",
             etransactions=[
              RawTransaction {
                taccount="assets:cash", 
                tamount=dollars 4.82,
                tcomment="",
                rttype=RegularTransaction
              },
              RawTransaction {
                taccount="equity:opening balances", 
                tamount=dollars (-4.82),
                tcomment="",
                rttype=RegularTransaction
              }
             ],
             epreceding_comment_lines=""
           }
          ,
           Entry {
             edate="2007/02/01", 
             estatus=False, 
             ecode="*", 
             edescription="ayres suites", 
             ecomment="",
             etransactions=[
              RawTransaction {
                taccount="expenses:vacation", 
                tamount=dollars 179.92,
                tcomment="",
                rttype=RegularTransaction
              },
              RawTransaction {
                taccount="assets:checking", 
                tamount=dollars (-179.92),
                tcomment="",
                rttype=RegularTransaction
              }
             ],
             epreceding_comment_lines=""
           }
          ,
           Entry {
             edate="2007/01/02", 
             estatus=False, 
             ecode="*", 
             edescription="auto transfer to savings", 
             ecomment="",
             etransactions=[
              RawTransaction {
                taccount="assets:saving", 
                tamount=dollars 200,
                tcomment="",
                rttype=RegularTransaction
              },
              RawTransaction {
                taccount="assets:checking", 
                tamount=dollars (-200),
                tcomment="",
                rttype=RegularTransaction
              }
             ],
             epreceding_comment_lines=""
           }
          ,
           Entry {
             edate="2007/01/03", 
             estatus=False, 
             ecode="*", 
             edescription="poquito mas", 
             ecomment="",
             etransactions=[
              RawTransaction {
                taccount="expenses:food:dining", 
                tamount=dollars 4.82,
                tcomment="",
                rttype=RegularTransaction
              },
              RawTransaction {
                taccount="assets:cash", 
                tamount=dollars (-4.82),
                tcomment="",
                rttype=RegularTransaction
              }
             ],
             epreceding_comment_lines=""
           }
          ,
           Entry {
             edate="2007/01/03", 
             estatus=False, 
             ecode="*", 
             edescription="verizon", 
             ecomment="",
             etransactions=[
              RawTransaction {
                taccount="expenses:phone", 
                tamount=dollars 95.11,
                tcomment="",
                rttype=RegularTransaction
              },
              RawTransaction {
                taccount="assets:checking", 
                tamount=dollars (-95.11),
                tcomment="",
                rttype=RegularTransaction
              }
             ],
             epreceding_comment_lines=""
           }
          ,
           Entry {
             edate="2007/01/03", 
             estatus=False, 
             ecode="*", 
             edescription="discover", 
             ecomment="",
             etransactions=[
              RawTransaction {
                taccount="liabilities:credit cards:discover", 
                tamount=dollars 80,
                tcomment="",
                rttype=RegularTransaction
              },
              RawTransaction {
                taccount="assets:checking", 
                tamount=dollars (-80),
                tcomment="",
                rttype=RegularTransaction
              }
             ],
             epreceding_comment_lines=""
           }
          ]
          ""

ledger7 = cacheLedger rawledger7 

timelogentry1_str  = "i 2007/03/11 16:19:00 hledger\n"
timelogentry1 = TimeLogEntry 'i' "2007/03/11 16:19:00" "hledger"

timelogentry2_str  = "o 2007/03/11 16:30:00\n"
timelogentry2 = TimeLogEntry 'o' "2007/03/11 16:30:00" ""

timelog1_str = concat [
                timelogentry1_str,
                timelogentry2_str
               ]
timelog1 = TimeLog [
            timelogentry1,
            timelogentry2
           ]

