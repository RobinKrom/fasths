-- |
-- Module      :  Codec.Fast.Data
-- Copyright   :  Robin S. Krom 2011
-- License     :  BSD3
-- 
-- Maintainer  :  Robin S. Krom
-- Stability   :  experimental
-- Portability :  unknown
--
{-#LANGUAGE TypeSynonymInstances, GeneralizedNewtypeDeriving, FlexibleInstances, GADTs, MultiParamTypeClasses, ExistentialQuantification, TypeFamilies, DeriveDataTypeable #-}

module Codec.Fast.Data 
(
TypeWitness (..),
Value (..),
Primitive (..),
Delta (..),
Templates (..),
Template (..),
TypeRef (..),
Instruction (..),
TemplateReferenceContent (..),
FieldInstrContent (..),
Field (..),
IntegerField (..),
DecimalField (..),
AsciiStringField (..),
UnicodeStringField (..),
ByteVectorField (..),
ByteVectorLength (..),
Sequence (..),
Group (..),
Length (..),
PresenceAttr (..),
FieldOp (..),
DecFieldOp (..),
Dictionary (..),
DictKey (..),
DictValue (..),
OpContext (..),
DictionaryAttr (..),
NsKey (..),
KeyAttr (..),
InitialValueAttr (..),
NsName (..),
TemplateNsName (..),
NameAttr (..),
NsAttr (..),
TemplateNsAttr (..),
IdAttr (..),
Token (..),
UnicodeString,
AsciiString,
Decimal,
anySBEEntity,
FASTException (..),
Context (..),
tname2fname,
fname2tname,
_anySBEEntity,
Coparser,
DualType,
contramap,
sequenceD,
prevValue,
updatePrevValue,
setPMap,
uniqueFName,
needsSegment,
needsPm,
tempRefCont2TempNsName
)

where

import Prelude hiding (exponent, dropWhile, reverse, zip)
import Data.ListLike (dropWhile, genericDrop, genericTake, genericLength, reverse, zip)
import Data.Char (digitToInt)
import Data.Bits
import qualified Data.ByteString as B
import Data.ByteString.Char8 (unpack, pack) 
import Data.Int
import Data.Word
import Data.Monoid
import qualified Data.Map as M
import qualified Data.Attoparsec as A
import qualified Data.Binary.Builder as BU
import Control.Applicative 
import Control.Monad.State
import Control.Exception
import Data.Typeable

-- | FAST exception.
data FASTException = S1 String
                   | S2 String
                   | S3 String
                   | S4 String 
                   | S5 String
                   | D1 String
                   | D2 String 
                   | D3 String
                   | D4 String
                   | D5 String
                   | D6 String
                   | D7 String
                   | D8 String
                   | D9 String
                   | D10 String
                   | D11 String
                   | D12 String
                   | R1 String
                   | R2 String
                   | R3 String
                   | R4 String
                   | R5 String 
                   | R6 String
                   | R7 String
                   | R8 String
                   | R9 String
                   | OtherException String
                   deriving (Show, Typeable)

instance Exception FASTException

-- |State of the (co)parser.
data Context = Context {
    -- |Presence map
    pm   :: [Bool],
    -- |Dictionaries.
    dict :: M.Map String Dictionary
    }

-- | We need type witnesses to handle manipulation of dictionaries with entries of all possible 
-- primitive types in generic code.
data TypeWitness a where 
    TypeWitnessI32   :: Int32         -> TypeWitness Int32
    TypeWitnessW32   :: Word32        -> TypeWitness Word32
    TypeWitnessI64   :: Int64         -> TypeWitness Int64
    TypeWitnessW64   :: Word64        -> TypeWitness Word64
    TypeWitnessASCII :: AsciiString   -> TypeWitness AsciiString
    TypeWitnessUNI   :: UnicodeString -> TypeWitness UnicodeString
    TypeWitnessBS    :: B.ByteString  -> TypeWitness B.ByteString
    TypeWitnessDec   :: Decimal       -> TypeWitness Decimal

type DualType a m = a -> m

contramap :: (a -> b) -> DualType b m -> DualType a m
contramap f cp = cp . f

append :: (Monoid m) => DualType a m -> DualType b m -> DualType (a, b) m
append cp1 cp2 (x, y) = cp1 x `mappend` cp2 y

append' :: (Monoid m) => DualType a m -> DualType a m -> DualType a m
append' cp1 cp2 = contramap (\x -> (x, x)) (cp1 `append` cp2)

sequenceD :: (Monoid m) => [DualType a m] -> DualType [a] m
sequenceD ds xs = mconcat (zipWith (\x d -> d x) xs ds)

type Coparser a = DualType a BU.Builder

-- | Primitive type class.
class Primitive a where
    data Delta a     :: *
    witnessType      :: a -> TypeWitness a
    assertType       :: (Primitive b) => TypeWitness b -> a
    toValue          :: a -> Value
    fromValue        :: Value -> a
    defaultBaseValue :: a
    ivToPrimitive    :: InitialValueAttr -> a
    delta            :: a -> Delta a -> a
    delta_           :: a -> a -> Delta a
    ftail            :: a -> a -> a
    ftail_           :: a -> a -> a
    decodeP          :: A.Parser a
    decodeD          :: A.Parser (Delta a)
    decodeT          :: A.Parser a
    encodeP          :: Coparser a
    encodeD          :: Coparser (Delta a)
    encodeT          :: Coparser a

    decodeT = decodeP
    encodeT = encodeP

-- |The values in a messages.
data Value = I32 Int32
           | UI32 Word32
           | I64 Int64
           | UI64 Word64
           | Dec Double
           | A  AsciiString
           | U  UnicodeString
           | B  B.ByteString
           | Sq Word32 [[(NsName, Maybe Value)]]
           | Gr [(NsName, Maybe Value)]
           deriving (Show)

-- |Some basic types, renamed for readability.
type UnicodeString = String
type AsciiString = String
type Decimal = (Int32, Int64)

instance Primitive Int32 where
    newtype Delta Int32 = Di32 Int32 deriving (Num, Ord, Show, Eq)
    witnessType = TypeWitnessI32
    assertType (TypeWitnessI32 i) = i
    assertType _ = throw $ D4 "Type mismatch."
    toValue = I32
    fromValue (I32 i) = i
    fromValue _ = throw $ D4 "Type mismatch."
    defaultBaseValue = 0 
    ivToPrimitive = read . trimWhiteSpace . text
    delta i (Di32 i') = i + i'
    delta_ i1 i2 = Di32 $ i1 - i2
    ftail = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    ftail_ = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    decodeP = int
    decodeD = Di32 <$> int
    decodeT = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    encodeP = _int
    encodeD  =  encodeP . (\(Di32 i) -> i)

instance Primitive Word32 where
    newtype Delta Word32 = Dw32 Int32 deriving (Num, Ord, Show, Eq)
    witnessType = TypeWitnessW32
    assertType (TypeWitnessW32 w) = w
    assertType _ = throw $ D4 "Type mismatch."
    toValue = UI32
    fromValue (UI32 i) = i
    fromValue _ = throw $ OtherException "Type mismatch."
    defaultBaseValue = 0
    ivToPrimitive = read . trimWhiteSpace . text
    delta w (Dw32 i) = fromIntegral (fromIntegral w + i)
    delta_ w1 w2 = Dw32 (fromIntegral w1 - fromIntegral w2)
    ftail = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    ftail_ = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    decodeP = uint
    decodeD = Dw32 <$> int
    decodeT = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    encodeP = _uint
    encodeD =  encodeP . (\(Dw32 w) -> w)

instance Primitive Int64 where
    newtype Delta Int64 = Di64 Int64 deriving (Num, Ord, Show, Eq)
    witnessType = TypeWitnessI64
    assertType (TypeWitnessI64 i) = i
    assertType _ = throw $ D4 "Type mismatch."
    toValue = I64
    fromValue (I64 i) = i
    fromValue _ = throw $ OtherException "Type mismatch."
    defaultBaseValue = 0
    ivToPrimitive = read . trimWhiteSpace . text
    delta i (Di64 i')= i + i'
    delta_ i1 i2 = Di64 (i1 - i2)
    ftail = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    ftail_ = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    decodeP = int
    decodeD = Di64 <$> int
    decodeT = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    encodeP = _int
    encodeD =  encodeP . (\(Di64 i) -> i)

instance Primitive Word64 where
    newtype Delta Word64 = Dw64 Int64 deriving (Num, Ord, Show, Eq)
    witnessType = TypeWitnessW64
    assertType (TypeWitnessW64 w) = w
    assertType _ = throw $ D4 "Type mismatch."
    toValue = UI64
    fromValue (UI64 i) = i
    fromValue _ = throw $ OtherException "Type mismatch."
    defaultBaseValue = 0
    ivToPrimitive = read . trimWhiteSpace . text
    delta w (Dw64 i) = fromIntegral (fromIntegral w + i)
    delta_ w1 w2 = Dw64 (fromIntegral w1 - fromIntegral w2)
    ftail = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields." 
    ftail_ = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    decodeP = uint
    decodeD = Dw64 <$> int
    decodeT = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    encodeP = _uint
    encodeD = encodeP . (\(Dw64 w) -> w)

instance Primitive AsciiString where
    newtype Delta AsciiString = Dascii (Int32, String)
    witnessType = TypeWitnessASCII
    assertType (TypeWitnessASCII s) = s
    assertType _ = throw $ D4 "Type mismatch."
    toValue = A
    fromValue (A s) = s
    fromValue _ = throw $ OtherException "Type mismatch."
    defaultBaseValue = ""
    ivToPrimitive = text
    delta s1 (Dascii (l, s2)) | l < 0 = s2 ++ s1' where s1' = genericDrop (-l) s1
    delta s1 (Dascii (l, s2)) | l >= 0 = s1' ++ s2 where s1' = genericTake (genericLength s1 - l) s1
    delta _ _ = throw $ D4 "Type mismatch."
    delta_ s1 s2 =  if ((genericLength l1) :: Int32) >= genericLength l2 
                    then Dascii (genericLength s2 - genericLength l1, genericDrop ((genericLength l1) :: Int32) s1)
                    else Dascii (genericLength l2 - genericLength s2, genericTake ((genericLength s1 - genericLength l2) :: Int32) s1)
                    where   l1 = map fst $ takeWhile (\(c1, c2) -> c1 == c2) (zip s1 s2)
                            l2 = map fst $ takeWhile (\(c1, c2) -> c1 == c2) (zip (reverse s1) (reverse s2))
                            
    ftail s1 s2 = take (length s1 - length s2) s1 ++ s2
    ftail_ s1 s2 = take (length s1 - length s2) s1
    decodeP = asciiString
    decodeD = do 
                l <- int
                s <- decodeP
                return (Dascii (l, s))
    decodeT = decodeP
    encodeP = _asciiString
    encodeD = (encodeP `append` encodeP) . (\(Dascii (i, s)) -> (i, s))

{-instance Primitive UnicodeString  where-}
    {-data TypeWitness UnicodeString = TypeWitnessUNI UnicodeString -}
    {-assertType (TypeWitnessUNI s) = s-}
    {-assertType _ = error "Type mismatch."-}
    {-type Delta UnicodeString = (Int32, B.ByteString)-}
    {-defaultBaseValue = ""-}
    {-ivToPrimitive = text-}
    {-delta s d =  B.unpack (delta (B.pack s) d)-}
    {-ftail s1 s2 = B.unpack (ftail (B.pack s1) s2)-}
    {-decodeP = B.unpack <$> byteVector-}
    {-decodeD = do-}
                {-l <- int-}
                {-bv <- decodeP-}
                {-return (l, bv)-}
    {-decodeT = decodeP-}

instance Primitive (Int32, Int64) where
    newtype Delta (Int32, Int64) = Ddec (Int32, Int64)
    witnessType = TypeWitnessDec
    assertType (TypeWitnessDec (e, m)) = (e, m)
    assertType _ = throw $ D4 "Type mismatch."
    toValue (e, m) = Dec $ encodeFloat (fromIntegral m) (fromIntegral e)
    fromValue (Dec d) = (fromIntegral $ snd d', fromIntegral $ fst d') where d' = decodeFloat d
    -- TODO: Might overflow for huge values in fromIntegral.
    fromValue _ = throw $ D4 "Type mismatch."
    defaultBaseValue = (0, 0)
    ivToPrimitive (InitialValueAttr s) = let    s' = trimWhiteSpace s 
                                                mant = read (filter (/= '.') s')
                                                expo = h s'
                                                h ('-':xs) = h xs
                                                h ('.':xs) = -1 * toEnum (length (takeWhile (=='0') xs) + 1)
                                                h ('0':'.':xs) = h ('.':xs)
                                                h xs = toEnum (length (takeWhile (/= '.') xs))
                                         in (mant, expo)
    delta (e1, m1) (Ddec (e2, m2)) = (e1 + e2, m1 + m2)
    delta_ (e2, m2) (e1, m1) = Ddec (e2 - e1, m2 - m1)
    ftail = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    ftail_ = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    decodeP = do 
        e <- int::A.Parser Int32
        m <- int::A.Parser Int64
        return (e, m)
    decodeD = Ddec <$> decodeP
    decodeT = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields."
    encodeP = encodeP `append` encodeP
    encodeD = encodeP . (\(Ddec (e, m)) -> (e, m))

instance Primitive B.ByteString where
    newtype Delta B.ByteString = Dbs (Int32, B.ByteString)
    witnessType = TypeWitnessBS
    assertType (TypeWitnessBS bs) = bs
    assertType _ = throw $ D4 "Type mismatch."
    toValue = B 
    fromValue (B bs) = bs
    fromValue _ = throw $ D4 "Type mismatch."
    defaultBaseValue = B.empty
    ivToPrimitive iv = B.pack (map (toEnum . digitToInt) (filter whiteSpace (text iv)))
    delta bv (Dbs (l, bv')) | l < 0 = bv'' `B.append` bv' where bv'' = genericDrop (-l) bv 
    delta bv (Dbs (l, bv')) | l >= 0 = bv'' `B.append` bv' where bv'' = genericTake (genericLength bv - l) bv
    delta _ _ = throw $ D4 "Type mismatch."
    delta_ bv1 bv2 =  if ((genericLength l1) :: Int32) >= genericLength l2 
                    then Dbs (genericLength bv2 - genericLength l1, genericDrop ((genericLength l1) :: Int32) bv1)
                    else Dbs (genericLength l2 - genericLength bv2, genericTake ((genericLength bv1 - genericLength l2) :: Int32) bv1)
                    where   l1 = map fst $ takeWhile (\(c1, c2) -> c1 == c2) (zip bv1 bv2)
                            l2 = map fst $ takeWhile (\(c1, c2) -> c1 == c2) (zip (reverse bv1) (reverse bv2))
    ftail b1 b2 = B.take (B.length b1 - B.length b2) b1 `B.append` b2
    ftail_ b1 b2 = B.take (B.length b1 - B.length b2) b1
    decodeP = byteVector
    decodeD = do 
                l <- int
                bv <- decodeP
                return (Dbs (l, bv))
    encodeP = _byteVector
    encodeD = (encodeP `append` encodeP) . (\(Dbs (i, bs)) -> (i, bs)) 

--
-- The following definitions follow allmost one to one the FAST specification.
--

-- |A collection of templates, i.e. a template file.
data Templates = Templates {
    tsNs              :: Maybe NsAttr,
    tsTemplateNs      :: Maybe TemplateNsAttr,
    tsDictionary      :: Maybe DictionaryAttr,
    tsTemplates       :: [Template]
    } deriving (Show)

-- |FAST template.
data Template = Template {
    tName         :: TemplateNsName,
    tNs           :: Maybe NsAttr,
    tDictionary   :: Maybe DictionaryAttr,
    tTypeRef      :: Maybe TypeRef,
    tInstructions :: [Instruction]
    } deriving (Show)

-- |A typeRef element of a template.
data TypeRef = TypeRef {
    trName :: NameAttr,
    trNs   :: Maybe NsAttr
    } deriving (Show)

-- |An Instruction in a template is either a field instruction or a template reference.
data Instruction = Instruction Field
                    |TemplateReference (Maybe TemplateReferenceContent)
                    deriving (Show)

-- |This is a helper data structure, NOT defined in the reference.
data TemplateReferenceContent = TemplateReferenceContent {
        trcName       :: NameAttr,
        trcTemplateNs :: Maybe TemplateNsAttr
        } deriving (Show)

tempRefCont2TempNsName :: TemplateReferenceContent -> TemplateNsName
tempRefCont2TempNsName (TemplateReferenceContent n maybe_ns) = TemplateNsName n maybe_ns Nothing 

-- |Field Instruction content.
data FieldInstrContent = FieldInstrContent {
    ficFName    :: NsName,
    ficPresence :: Maybe PresenceAttr,
    ficFieldOp  :: Maybe FieldOp
    } deriving (Show)

-- |FAST field instructions.
data Field = IntField IntegerField
           | DecField DecimalField
           | AsciiStrField AsciiStringField
           | UnicodeStrField UnicodeStringField
           | ByteVecField ByteVectorField
           | Seq Sequence
           | Grp Group
			deriving (Show)

-- |Integer Fields.
data IntegerField = Int32Field FieldInstrContent
                    |UInt32Field FieldInstrContent
                    |Int64Field FieldInstrContent
                    |UInt64Field FieldInstrContent
                    deriving (Show)

-- |Decimal Field.
data DecimalField = DecimalField {
        dfiFName    :: NsName,
        dfiPresence :: Maybe PresenceAttr,
        dfiFieldOp  :: Maybe (Either FieldOp DecFieldOp)
        } deriving (Show)

-- |Ascii string field.
data AsciiStringField = AsciiStringField FieldInstrContent deriving (Show)

-- |Unicode string field.
data UnicodeStringField = UnicodeStringField {
        usfContent :: FieldInstrContent,
        usfLength  :: Maybe ByteVectorLength
        } deriving (Show)

-- |Bytevector field.
data ByteVectorField = ByteVectorField {
        bvfContent :: FieldInstrContent,
        bvfLength  :: Maybe ByteVectorLength
        } deriving (Show)

-- |Sequence field.
data Sequence = Sequence {
        sFName        :: NsName,
        sPresence     :: Maybe PresenceAttr,
        sDictionary   :: Maybe DictionaryAttr,
        sTypeRef      :: Maybe TypeRef,
        sLength       :: Maybe Length,
        sInstructions :: [Instruction]
        } deriving (Show)

-- |Group field.
data Group = Group {
        gFName        :: NsName,
        gPresence     :: Maybe PresenceAttr,
        gDictionary   :: Maybe DictionaryAttr,
        gTypeRef      :: Maybe TypeRef,
        gInstructions :: [Instruction]
        } deriving (Show)

-- |ByteVectorLenght is logically a uInt32, but it is not a field instruction 
-- and it is not physically present in the stream. Obviously no field operator 
-- is needed.
data ByteVectorLength = ByteVectorLength {
    bvlNsName::NsName
    } deriving (Show)

-- |SeqLength is logically a uInt32. The name maybe 'implicit' or 'explicit' 
-- in the template.
-- implicit: the name is generated and is unique to the name of the sequence 
-- field.
-- explicit: the name is explicitly given in the template.
-- If the length field is not present in the template, the length field has an 
-- implicit name and the length of the sequence is not present in the stream 
-- and therefore the length field neither contains a field operator.
data Length = Length {
    lFName   :: Maybe NsName,
    lFieldOp :: Maybe FieldOp
    } deriving (Show)


-- |Presence of a field value is either mandatory or optional.
data PresenceAttr = Mandatory | Optional deriving (Show)

-- |FAST field operators.
data FieldOp = Constant InitialValueAttr
             | Default (Maybe InitialValueAttr)
             | Copy OpContext
             | Increment OpContext
             | Delta OpContext
             | Tail OpContext
				deriving (Show)
 
-- |The decimal field operator consists of two standart operators.
data DecFieldOp = DecFieldOp {
    dfoExponent :: Maybe FieldOp,
    dfoMantissa :: Maybe FieldOp
    } deriving (Show)

-- |Dictionary consists of a name and a list of key value pairs.
data Dictionary = Dictionary String (M.Map DictKey DictValue)

data DictKey = N NsName
             | K NsKey
				deriving (Eq, Ord, Show)


-- |Entry in a dictionary can be in one of three states.
data DictValue = Undefined
               | Empty
               | forall a. Primitive a => Assigned (TypeWitness a)

-- |Operator context.
data OpContext = OpContext {
    ocDictionary   :: Maybe DictionaryAttr,
    ocNsKey        :: Maybe NsKey,
    ocInitialValue :: Maybe InitialValueAttr
    } deriving (Show)

-- |Dictionary attribute. Three predefined dictionaries are "template", "type" 
-- and "global".
data DictionaryAttr = DictionaryAttr String deriving (Show)

-- |nsKey attribute.
data NsKey = NsKey {
    nkKey :: KeyAttr,
    nkNs  :: Maybe NsAttr
    } deriving (Eq, Ord, Show)

-- |Key attribute.
data KeyAttr = KeyAttr {
    kaToken :: Token
    } deriving (Eq, Ord, Show)

-- |Initial value attribute. The value is a string of unicode characters and needs to 
-- be converted to the type of the field in question.
data InitialValueAttr = InitialValueAttr {
    text :: UnicodeString
    } deriving (Show)

-- |A full name in a template is given by a namespace URI and localname. For 
-- application types, fields and operator keys the namespace URI is given by 
-- the 'ns' attribute. For templates the namespace URI is given by the 
-- 'templateNs' attribute.
-- Note that full name constructors in the data structures are named 'fname'.

-- |A full name for an application type, field or operator key.
data NsName = NsName NameAttr (Maybe NsAttr) (Maybe IdAttr) deriving (Eq, Ord, Show)

-- |A full name for a template.
data TemplateNsName = TemplateNsName NameAttr (Maybe TemplateNsAttr) (Maybe IdAttr) deriving (Show, Eq, Ord)

-- |Translates a TemplateNsName into a NsName. Its the same anyway.
tname2fname :: TemplateNsName -> NsName
tname2fname (TemplateNsName n (Just (TemplateNsAttr ns)) maybe_id) = NsName n (Just (NsAttr ns)) maybe_id
tname2fname (TemplateNsName n Nothing maybe_id) = NsName n Nothing maybe_id

fname2tname :: NsName -> TemplateNsName
fname2tname (NsName n (Just (NsAttr ns)) maybe_id) = TemplateNsName n (Just (TemplateNsAttr ns)) maybe_id
fname2tname (NsName n Nothing maybe_id) = TemplateNsName n Nothing maybe_id

-- |The very basic name related attributes.
newtype NameAttr = NameAttr String deriving (Eq, Ord, Show)
newtype NsAttr = NsAttr String deriving (Eq, Ord, Show)
newtype TemplateNsAttr = TemplateNsAttr String deriving (Eq, Ord, Show)
newtype IdAttr = IdAttr Token deriving (Eq, Ord, Show)
newtype Token = Token String deriving (Eq, Ord, Show)


-- |Get a Stopbit encoded entity.
anySBEEntity :: A.Parser B.ByteString
anySBEEntity = takeTill' stopBitSet

_anySBEEntity :: Coparser B.ByteString
_anySBEEntity bs = BU.fromByteString (B.init bs `B.append` B.singleton (setBit (B.last bs) 7))

-- |Like takeTill, but takes the matching byte as well.
takeTill' :: (Word8 -> Bool) -> A.Parser B.ByteString
takeTill' f = do
    str <- A.takeTill f
    c <- A.take 1
    return (str `B.append` c)

-- |Test wether the stop bit is set of a Char. (Note: Chars are converted to
-- Word8's. 
-- TODO: Is this unsafe?
stopBitSet :: Word8 -> Bool
stopBitSet c = testBit c 7

-- |Bytevector size preamble parser.
byteVector :: A.Parser B.ByteString
byteVector = do
    s <- uint::A.Parser Word32
    byteVector' s

-- |Bytevector field parser. The first argument is the size of the bytevector.
-- If the length of the bytevector is bigger than maxBound::Int an exception 
-- will be trown.
byteVector' :: Word32 -> A.Parser B.ByteString
byteVector' c = A.take (fromEnum c)

_byteVector :: Coparser B.ByteString
_byteVector = (_uint . (\bs -> fromIntegral(B.length bs) :: Word32)) `append'` BU.fromByteString

-- |Unsigned integer parser, doesn't check for bounds.
-- TODO: should we check for R6 errors, i.e overlong fields?
uint :: (Bits a) => A.Parser a
uint = do 
    bs <- anySBEEntity
    return (B.foldl h 0 bs)
    where   h::(Bits a, Num a) => a -> Word8 -> a
            h r w = fromIntegral (clearBit w 7) .|. shiftL r 7
        
_uint :: (Bits a, Eq a, Integral a) => Coparser a
_uint = _anySBEEntity . uintBS 

uintBS :: (Bits a, Eq a, Integral a) => a -> B.ByteString
uintBS ui = if ui' /= 0 
            then uintBS ui' `B.snoc` (fromIntegral (ui .&. 127) :: Word8)
            else B.empty
            where ui' = shiftR ui 7

-- |Signed integer parser, doesn't check for bounds.
int :: (Bits a) => A.Parser a
int = do
    bs <- anySBEEntity
    return (if testBit (B.head bs) 6 
            then B.foldl h (shiftL (-1) 7 .|. fromIntegral (setBit (B.head bs) 7)) (B.tail bs)
            else B.foldl h 0 bs)
    where   
            h::(Bits a, Num a) => a -> Word8 -> a
            h r w = fromIntegral (clearBit w 7) .|. shiftL r 7

_int :: (Bits a, Ord a, Integral a) => Coparser a
_int  = _anySBEEntity . intBS 

intBS :: (Bits a, Ord a, Integral a) => a -> B.ByteString
intBS i =    if i < 0 
             then setBit (B.head (uintBS i)) 6 `B.cons` B.tail (uintBS i)
             else uintBS i

-- |ASCII string field parser, non-Nullable.
asciiString :: A.Parser AsciiString
asciiString = do
    bs <- anySBEEntity
    let bs' = B.init bs `mappend` B.singleton (clearBit (B.last bs) 7) in
        return (unpack bs')

_asciiString :: Coparser AsciiString
_asciiString = _anySBEEntity . pack 

trimWhiteSpace :: String -> String
trimWhiteSpace = reverse . dropWhile whiteSpace . reverse . dropWhile whiteSpace

whiteSpace :: Char -> Bool
whiteSpace c =  c `elem` " \t\r\n"

-- *Previous value related functions.

-- |Get previous value.
prevValue :: (Monad m) => NsName -> OpContext -> StateT Context m DictValue
prevValue name (OpContext (Just (DictionaryAttr dname)) Nothing _ ) 
    = pv dname (N name)

prevValue _ (OpContext (Just (DictionaryAttr dname)) (Just dkey) _ ) 
    = pv dname (K dkey)

prevValue name (OpContext Nothing Nothing _ ) 
    = pv "global" (N name)

prevValue _ (OpContext Nothing (Just dkey) _ ) 
    = pv "global" (K dkey)

pv :: (Monad m) => String -> DictKey -> StateT Context m DictValue
pv d k = do
       st <- get
       case M.lookup d (dict st) >>= \(Dictionary _ xs) -> M.lookup k xs of
        Nothing -> throw $ OtherException ("Could not find specified dictionary/key." ++ show d ++ " " ++ show k)
        Just dv -> return dv

-- |Update the previous value.
updatePrevValue :: (Monad m) => NsName -> OpContext -> DictValue -> StateT Context m ()
updatePrevValue name (OpContext (Just (DictionaryAttr dname)) Nothing _ ) dvalue
    = uppv dname (N name) dvalue

updatePrevValue _ (OpContext (Just (DictionaryAttr dname)) (Just dkey) _ ) dvalue
    = uppv dname (K dkey) dvalue

updatePrevValue name (OpContext Nothing Nothing _ ) dvalue
    = uppv "global" (N name) dvalue

updatePrevValue _ (OpContext Nothing (Just dkey) _ ) dvalue
    = uppv "global" (K dkey) dvalue

uppv :: (Monad m) => String -> DictKey -> DictValue -> StateT Context m ()
uppv d k v = do
    st <- get
    put (Context (pm st) (M.adjust (\(Dictionary n xs) -> Dictionary n (M.adjust (\_ -> v) k xs)) d (dict st)))

setPMap :: (Monad m) => Bool -> StateT Context m ()
setPMap b = do 
                 st <- get
                 put (Context ((pm st) ++ [b]) (dict st))

-- |Create a unique fname out of a given one and a string.
uniqueFName::NsName -> String -> NsName
uniqueFName fname s = NsName (NameAttr(n ++ s)) ns ide
    where (NsName (NameAttr n) ns ide) = fname

needsSegment ::[Instruction] -> M.Map TemplateNsName Template -> Bool
needsSegment ins ts = any (needsPm ts) ins 

-- |Decides wether an instruction uses the presence map or not. We need to know all the templates,
-- to process template reference instructions recursivly.
needsPm::M.Map TemplateNsName Template -> Instruction -> Bool
-- static template reference
needsPm ts (TemplateReference (Just trc)) = all (needsPm ts) (tInstructions t) where t = ts M.! (tempRefCont2TempNsName trc)
-- dynamic template reference
needsPm _ (TemplateReference Nothing) = False
needsPm _ (Instruction (IntField (Int32Field fic))) = intFieldNeedsPm fic
needsPm _ (Instruction (IntField (Int64Field fic))) = intFieldNeedsPm fic
needsPm _ (Instruction (IntField (UInt32Field fic))) = intFieldNeedsPm fic
needsPm _ (Instruction (IntField (UInt64Field fic))) = intFieldNeedsPm fic
needsPm ts (Instruction (DecField (DecimalField fname Nothing eitherOp))) = needsPm ts (Instruction(DecField (DecimalField fname (Just Mandatory) eitherOp)))
needsPm _ (Instruction (DecField (DecimalField _ (Just Mandatory) Nothing ))) = False
needsPm _ (Instruction (DecField (DecimalField _ (Just Mandatory) (Just (Left (Constant _)))))) = False
needsPm _ (Instruction (DecField (DecimalField _ (Just Mandatory) (Just (Left (Default _)))))) = True
needsPm _ (Instruction (DecField (DecimalField _ (Just Mandatory) (Just (Left (Copy _)))))) = True
needsPm _ (Instruction (DecField (DecimalField _ (Just Mandatory) (Just (Left (Increment _)))))) = throw $ S2 "Increment operator is only applicable to integer fields." 
needsPm _ (Instruction (DecField (DecimalField _ (Just Mandatory) (Just (Left (Delta _)))))) = False
needsPm _ (Instruction (DecField (DecimalField _ (Just Mandatory) (Just (Left (Tail _)))))) = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields." 
needsPm _ (Instruction (DecField (DecimalField _ (Just Optional) Nothing ))) = False
needsPm _ (Instruction (DecField (DecimalField _ (Just Optional) (Just (Left (Constant _)))))) = True
needsPm _ (Instruction (DecField (DecimalField _ (Just Optional) (Just (Left (Default _)))))) = True 
needsPm _ (Instruction (DecField (DecimalField _ (Just Optional) (Just (Left (Copy _)))))) = True
needsPm _ (Instruction (DecField (DecimalField _ (Just Optional) (Just (Left (Increment _)))))) = throw $ S2 "Increment operator is only applicable to integer fields." 
needsPm _ (Instruction (DecField (DecimalField _ (Just Optional) (Just (Left (Delta _)))))) = False
needsPm _ (Instruction (DecField (DecimalField _ (Just Optional) (Just (Left (Tail _)))))) = throw $ S2 "Tail operator is only applicable to ascii, unicode and bytevector fields." 
needsPm ts (Instruction (DecField (DecimalField fname (Just Mandatory) (Just (Right (DecFieldOp maybe_opE maybe_opM)))))) = needsPm ts insE && needsPm ts insM 
    where   insE = Instruction (IntField (Int32Field (FieldInstrContent fname (Just Mandatory) maybe_opE)))
            insM =  Instruction (IntField (Int64Field (FieldInstrContent fname (Just Mandatory) maybe_opM)))
needsPm ts (Instruction (DecField (DecimalField fname (Just Optional) (Just (Right (DecFieldOp maybe_opE maybe_opM)))))) = needsPm ts insE && needsPm ts insM 
    where   insE = Instruction (IntField (Int32Field (FieldInstrContent fname (Just Optional) maybe_opE)))
            insM =  Instruction (IntField (Int64Field (FieldInstrContent fname (Just Mandatory) maybe_opM)))
needsPm ts (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent fname Nothing maybeOp)))) = needsPm ts (Instruction(AsciiStrField (AsciiStringField (FieldInstrContent fname (Just Mandatory) maybeOp))))
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Mandatory) Nothing)))) = False
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Mandatory) (Just (Constant _)))))) = False
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Mandatory) (Just (Default _)))))) = True
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Mandatory) (Just (Copy _)))))) = True
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Mandatory) (Just (Increment _)))))) = throw $ S2 "Increment operator is only applicable to integer fields." 
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Mandatory) (Just (Delta _)))))) =  False
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Mandatory) (Just (Tail _)))))) = True
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Optional) Nothing)))) = False
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Optional) (Just (Constant _)))))) = True
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Optional) (Just (Default _)))))) = True
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Optional) (Just (Copy _)))))) = True
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Optional) (Just (Increment _)))))) = throw $ S2 "Increment operator is only applicable to integer fields." 
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Optional) (Just (Delta _)))))) = False
needsPm _ (Instruction (AsciiStrField (AsciiStringField (FieldInstrContent _ (Just Optional) (Just (Tail _)))))) = True
needsPm ts (Instruction (ByteVecField (ByteVectorField (FieldInstrContent fname Nothing maybeOp) maybe_length))) = needsPm ts (Instruction(ByteVecField (ByteVectorField (FieldInstrContent fname (Just Mandatory) maybeOp) maybe_length)))
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) Nothing) _))) = False
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) Nothing) _))) = False
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) (Just (Constant _))) _))) = False
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) (Just (Constant _))) _))) = True
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) (Just (Default Nothing))) _))) = throw $ S5 " No initial value given for mandatory default operator."
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) (Just (Default (Just _)))) _))) = True
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) (Just (Default Nothing))) _))) = True
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) (Just(Default (Just _)))) _))) = True
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) (Just(Copy _ ))) _))) = True
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) (Just(Copy _ ))) _))) = True
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) (Just (Increment _))) _))) = throw $ S2 "Increment operator is only applicable to integer fields." 
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) (Just(Increment _))) _))) = throw $ S2 "Increment operator is only applicable to integer fields." 
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) (Just(Delta _))) _))) = False
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) (Just(Delta _))) _))) = False
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Mandatory) (Just(Tail _))) _))) = True
needsPm _ (Instruction (ByteVecField (ByteVectorField (FieldInstrContent _ (Just Optional) (Just(Tail _))) _))) = True
needsPm ts (Instruction (UnicodeStrField (UnicodeStringField (FieldInstrContent fname maybe_presence maybe_op) maybe_length))) = needsPm ts (Instruction(ByteVecField (ByteVectorField (FieldInstrContent fname maybe_presence maybe_op) maybe_length)))
needsPm ts (Instruction (Seq s)) = all h (sInstructions s)
    where   h (TemplateReference Nothing) = False
            h (TemplateReference (Just trc)) = all (needsPm ts) (tInstructions (ts M.! (tempRefCont2TempNsName trc)))
            h f = needsPm ts f
needsPm ts (Instruction (Grp g)) = all h (gInstructions g)
    where   h (TemplateReference Nothing) = False
            h (TemplateReference (Just trc)) = all (needsPm ts) (tInstructions (ts M.! (tempRefCont2TempNsName trc)))
            h f = needsPm ts f

-- |Maps a integer field to a triple (DictionaryName, Key, Value).
intFieldNeedsPm::FieldInstrContent -> Bool
intFieldNeedsPm (FieldInstrContent fname Nothing maybeOp) = intFieldNeedsPm $ FieldInstrContent fname (Just Mandatory) maybeOp
intFieldNeedsPm (FieldInstrContent _ (Just Mandatory) Nothing) = False
intFieldNeedsPm (FieldInstrContent _ (Just Mandatory) (Just (Constant _))) = False
intFieldNeedsPm (FieldInstrContent _ (Just Mandatory) (Just (Default _))) = True
intFieldNeedsPm (FieldInstrContent _ (Just Mandatory) (Just (Copy _))) = True
intFieldNeedsPm (FieldInstrContent _ (Just Mandatory) (Just (Increment _))) = True
intFieldNeedsPm (FieldInstrContent _ (Just Mandatory) (Just (Delta _))) = False
intFieldNeedsPm (FieldInstrContent _ (Just Mandatory) (Just (Tail _))) = throw $ S2 " Tail operator can not be applied on an integer type field." 
intFieldNeedsPm (FieldInstrContent _ (Just Optional) Nothing) = False
intFieldNeedsPm (FieldInstrContent _ (Just Optional) (Just (Constant _))) = True
intFieldNeedsPm (FieldInstrContent _ (Just Optional) (Just (Default _))) = True
intFieldNeedsPm (FieldInstrContent _ (Just Optional) (Just (Copy _))) = True
intFieldNeedsPm (FieldInstrContent _ (Just Optional) (Just (Increment _))) = True
intFieldNeedsPm (FieldInstrContent _ (Just Optional) (Just (Delta _))) = False
intFieldNeedsPm (FieldInstrContent _ (Just Optional) (Just (Tail _))) = throw $ S2 " Tail operator can not be applied on an integer type field." 
