module xlld.wrap;

import xlld.xlcall;
import xlld.traits: isSupportedFunction;
import xlld.memorymanager: autoFree;
import xlld.framework: freeXLOper;
import xlld.worksheet;
import xlld.any: Any;
import std.traits: Unqual;



version(unittest) {
    import unit_threaded;
    import xlld.test_util: TestAllocator, shouldEqualDlang, toSRef;
    import std.experimental.allocator.mallocator: Mallocator;
    import std.experimental.allocator.gc_allocator: GCAllocator;
    import xlld.any: any;
    alias theMallocator = Mallocator.instance;
    alias theGC = GCAllocator.instance;
}

XLOPER12 toXlOper(T, A)(in T val, ref A allocator) if(is(T == int)) {
    auto ret = XLOPER12();
    ret.xltype = XlType.xltypeInt;
    ret.val.w = val;
    return ret;
}


XLOPER12 toXlOper(T, A)(in T val, ref A allocator) if(is(T == double)) {
    auto ret = XLOPER12();
    ret.xltype = XlType.xltypeNum;
    ret.val.num = val;
    return ret;
}

__gshared immutable toXlOperMemoryException = new Exception("Failed to allocate memory for string oper");
__gshared immutable toXlOperShapeException = new Exception("# of columns must all be the same and aren't");

XLOPER12 toXlOper(T, A)(in T val, ref A allocator)
    if(is(T == string) || is(T == wstring))
{
    import std.utf: byWchar;

    auto wval = cast(wchar*)allocator.allocate(numOperStringBytes(val)).ptr;
    if(wval is null)
        throw toXlOperMemoryException;

    int i = 1;
    foreach(ch; val.byWchar) {
        wval[i++] = ch;
    }

    wval[0] = cast(ushort)(i - 1);

    auto ret = XLOPER12();
    ret.xltype = XlType.xltypeStr;
    ret.val.str = cast(XCHAR*)wval;

    return ret;
}

@("toXlOper!string utf8")
@system unittest {
    import std.conv: to;
    import xlld.memorymanager: allocator;

    const str = "foo";
    auto oper = str.toXlOper(allocator);
    scope(exit) freeXLOper(&oper, allocator);

    oper.xltype.shouldEqual(xltypeStr);
    (cast(int)oper.val.str[0]).shouldEqual(str.length);
    (cast(wchar*)oper.val.str)[1 .. str.length + 1].to!string.shouldEqual(str);
}

@("toXlOper!string utf16")
@system unittest {
    import xlld.memorymanager: allocator;

    const str = "foo"w;
    auto oper = str.toXlOper(allocator);
    scope(exit) freeXLOper(&oper, allocator);

    oper.xltype.shouldEqual(xltypeStr);
    (cast(int)oper.val.str[0]).shouldEqual(str.length);
    (cast(wchar*)oper.val.str)[1 .. str.length + 1].shouldEqual(str);
}

@("toXlOper!string TestAllocator")
@system unittest {
    auto allocator = TestAllocator();
    auto oper = "foo".toXlOper(allocator);
    allocator.numAllocations.shouldEqual(1);
    freeXLOper(&oper, allocator);
}

@("toXlOper!string unicode")
@system unittest {
    import std.utf: byWchar;
    import std.array: array;

    "é".byWchar.array.length.shouldEqual(1);
    "é"w.byWchar.array.length.shouldEqual(1);

    auto oper = "é".toXlOper(theGC);
    const ushort length = oper.val.str[0];
    length.shouldEqual("é"w.length);
}

// the number of bytes required to store `str` as an XLOPER12 string
package size_t numOperStringBytes(T)(in T str) if(is(T == string) || is(T == wstring)) {
    // XLOPER12 strings are wide strings where index 0 is the length
    // and [1 .. $] is the actual string
    return (str.length + 1) * wchar.sizeof;
}

package size_t numOperStringBytes(ref const(XLOPER12) oper) @trusted @nogc pure nothrow {
    // XLOPER12 strings are wide strings where index 0 is the length
    // and [1 .. $] is the actual string
    if(oper.xltype != XlType.xltypeStr) return 0;
    return (oper.val.str[0] + 1) * wchar.sizeof;
}


XLOPER12 toXlOper(T, A)(T[][] values, ref A allocator)
    if(is(T == double) || is(T == string) || is(Unqual!T == Any))
{
    import std.algorithm: map, all;
    import std.array: array;

    if(!values.all!(a => a.length == values[0].length))
       throw toXlOperShapeException;

    const rows = cast(int)values.length;
    const cols = values.length ? cast(int)values[0].length : 0;
    auto ret = multi(rows, cols, allocator);
    auto opers = ret.val.array.lparray[0 .. rows*cols];

    int i;
    foreach(ref row; values) {
        foreach(ref val; row) {
            opers[i++] = val.toXlOper(allocator);
        }
    }

    return ret;
}


@("toXlOper string[][]")
@system unittest {
    import xlld.memorymanager: allocator;

    auto oper = [["foo", "bar", "baz"], ["toto", "titi", "quux"]].toXlOper(allocator);
    scope(exit) freeXLOper(&oper, allocator);

    oper.xltype.shouldEqual(xltypeMulti);
    oper.val.array.rows.shouldEqual(2);
    oper.val.array.columns.shouldEqual(3);
    auto opers = oper.val.array.lparray[0 .. oper.val.array.rows * oper.val.array.columns];

    opers[0].shouldEqualDlang("foo");
    opers[3].shouldEqualDlang("toto");
    opers[5].shouldEqualDlang("quux");
}

@("toXlOper string[][]")
@system unittest {
    TestAllocator allocator;
    auto oper = [["foo", "bar", "baz"], ["toto", "titi", "quux"]].toXlOper(allocator);
    allocator.numAllocations.shouldEqual(7);
    freeXLOper(&oper, allocator);
}

@("toXlOper double[][]")
@system unittest {
    TestAllocator allocator;
    auto oper = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]].toXlOper(allocator);
    allocator.numAllocations.shouldEqual(1);
    freeXLOper(&oper, allocator);
}

__gshared immutable multiMemoryException = new Exception("Failed to allocate memory for multi oper");

private XLOPER12 multi(A)(int rows, int cols, ref A allocator) {
    auto ret = XLOPER12();

    ret.xltype = XlType.xltypeMulti;
    ret.val.array.rows = rows;
    ret.val.array.columns = cols;

    ret.val.array.lparray = cast(XLOPER12*)allocator.allocate(rows * cols * ret.sizeof).ptr;
    if(ret.val.array.lparray is null)
        throw multiMemoryException;

    return ret;
}


XLOPER12 toXlOper(T, A)(T values, ref A allocator) if(is(T == string[]) || is(T == double[])) {
    T[1] realValues = [values];
    return realValues.toXlOper(allocator);
}


@("toXlOper string[]")
@system unittest {
    TestAllocator allocator;
    auto oper = ["foo", "bar", "baz", "toto", "titi", "quux"].toXlOper(allocator);
    allocator.numAllocations.shouldEqual(7);
    freeXLOper(&oper, allocator);
}

XLOPER12 toXlOper(T, A)(T value, ref A allocator) if(is(Unqual!T == Any)) {
    return value._impl;
}

@("toXlOper any double")
unittest {
    any(5.0, Mallocator.instance).toXlOper(theMallocator).shouldEqualDlang(5.0);
}

@("toXlOper any string")
unittest {
    any("foo", Mallocator.instance).toXlOper(theMallocator).shouldEqualDlang("foo");
}

@("toXlOper any double[][]")
unittest {
    any([[1.0, 2.0], [3.0, 4.0]], Mallocator.instance)
        .toXlOper(theMallocator).shouldEqualDlang([[1.0, 2.0], [3.0, 4.0]]);
}

@("toXlOper any string[][]")
unittest {
    any([["foo", "bar"], ["quux", "toto"]], Mallocator.instance)
        .toXlOper(theMallocator).shouldEqualDlang([["foo", "bar"], ["quux", "toto"]]);
}


XLOPER12 toXlOper(T, A)(T value, ref A allocator) if(is(Unqual!T == Any[])) {
    return [value].toXlOper(allocator);
}

@("toXlOper any[]")
unittest {
    import xlld.memorymanager: allocatorContext;

    with(allocatorContext(Mallocator.instance)) {
        auto oper = toXlOper([any(42.0), any("foo")]);
        oper.xltype.shouldEqual(XlType.xltypeMulti);
        oper.val.array.lparray[0].shouldEqualDlang(42.0);
        oper.val.array.lparray[1].shouldEqualDlang("foo");
    }
}


@("toXlOper mixed 1D array of any")
unittest {
    const a = any([any(1.0, theMallocator), any("foo", theMallocator)],
                  theMallocator);
    auto oper = a.toXlOper(theMallocator);
    oper.xltype.shouldEqual(XlType.xltypeMulti);

    const rows = oper.val.array.rows;
    const cols = oper.val.array.columns;
    auto opers = oper.val.array.lparray[0 .. rows * cols];
    opers[0].shouldEqualDlang(1.0);
    opers[1].shouldEqualDlang("foo");
    autoFree(&oper); // normally this is done by Excel
}

@("toXlOper any[][]")
unittest {
    import xlld.memorymanager: allocatorContext;

    with(allocatorContext(Mallocator.instance)) {
        auto oper = toXlOper([[any(42.0), any("foo"), any("quux")], [any("bar"), any(7.0), any("toto")]]);
        oper.xltype.shouldEqual(XlType.xltypeMulti);
        oper.val.array.rows.shouldEqual(2);
        oper.val.array.columns.shouldEqual(3);
        oper.val.array.lparray[0].shouldEqualDlang(42.0);
        oper.val.array.lparray[1].shouldEqualDlang("foo");
        oper.val.array.lparray[2].shouldEqualDlang("quux");
        oper.val.array.lparray[3].shouldEqualDlang("bar");
        oper.val.array.lparray[4].shouldEqualDlang(7.0);
        oper.val.array.lparray[5].shouldEqualDlang("toto");
    }
}


@("toXlOper mixed 2D array of any")
unittest {
    const a = any([
                     [any(1.0, theMallocator), any(2.0, theMallocator)],
                     [any("foo", theMallocator), any("bar", theMallocator)]
                 ],
                 theMallocator);
    auto oper = a.toXlOper(theMallocator);
    oper.xltype.shouldEqual(XlType.xltypeMulti);

    const rows = oper.val.array.rows;
    const cols = oper.val.array.columns;
    auto opers = oper.val.array.lparray[0 .. rows * cols];
    opers[0].shouldEqualDlang(1.0);
    opers[1].shouldEqualDlang(2.0);
    opers[2].shouldEqualDlang("foo");
    opers[3].shouldEqualDlang("bar");
    autoFree(&oper); // normally this is done by Excel
}

XLOPER12 toXlOper(T, A)(T value, ref A allocator) if(is(T == int)) {
    XLOPER12 ret;
    ret.xltype = XlType.xltypeInt;
    ret.val.w = value;
    return ret;
}

@("toExcelOper!int")
unittest {
    auto oper = 42.toXlOper(theMallocator);
    oper.xltype.shouldEqual(XlType.xltypeInt);
    oper.val.w.shouldEqual(42);
}

auto fromXlOper(T, A)(ref XLOPER12 val, ref A allocator) {
    return (&val).fromXlOper!T(allocator);
}

// RValue overload
auto fromXlOper(T, A)(XLOPER12 val, ref A allocator) {
    return fromXlOper!T(val, allocator);
}

auto fromXlOper(T, A)(LPXLOPER12 val, ref A allocator) if(is(T == double)) {
    if(val.xltype == xltypeMissing)
        return double.init;

    return val.val.num;
}

@("fromXlOper!double")
@system unittest {

    TestAllocator allocator;
    auto num = 4.0;
    auto oper = num.toXlOper(allocator);
    auto back = oper.fromXlOper!double(allocator);
    back.shouldEqual(num);

    freeXLOper(&oper, allocator);
}


@("isNan for fromXlOper!double")
@system unittest {
    import std.math: isNaN;
    import xlld.memorymanager: allocator;
    XLOPER12 oper;
    oper.xltype = XlType.xltypeMissing;
    fromXlOper!double(&oper, allocator).isNaN.shouldBeTrue;
}

auto fromXlOper(T, A)(LPXLOPER12 val, ref A allocator) if(is(T == int)) {
    if(val.xltype == xltypeMissing)
        return int.init;

    return val.val.w;
}

@system unittest {
    42.toXlOper(theGC).fromXlOper!int(theGC).shouldEqual(42);
}

@("0 for fromXlOper!int missing oper")
@system unittest {
    XLOPER12 oper;
    oper.xltype = XlType.xltypeMissing;
    oper.fromXlOper!int(theGC).shouldEqual(0);
}

__gshared immutable fromXlOperMemoryException = new Exception("Could not allocate memory for array of char");
__gshared immutable fromXlOperConvException = new Exception("Could not convert double to string");

auto fromXlOper(T, A)(LPXLOPER12 val, ref A allocator) if(is(T == string)) {

    import std.experimental.allocator: makeArray;
    import std.utf: byChar;
    import std.range: walkLength;

    const stripType = stripMemoryBitmask(val.xltype);
    if(stripType != XlType.xltypeStr && stripType != XlType.xltypeNum)
        return null;


    if(stripType == XlType.xltypeStr) {

        auto chars = val.val.str[1 .. val.val.str[0] + 1].byChar;
        const length = chars.save.walkLength;
        auto ret = allocator.makeArray!char(length);

        if(ret is null && length > 0)
            throw fromXlOperMemoryException;

        int i;
        foreach(ch; val.val.str[1 .. val.val.str[0] + 1].byChar)
            ret[i++] = ch;

        return cast(string)ret;
    } else {
        // if a double, try to convert it to a string
        import core.stdc.stdio: snprintf;
        char[1024] buffer;
        const numChars = snprintf(&buffer[0], buffer.length, "%lf", val.val.num);
        if(numChars > buffer.length - 1)
            throw fromXlOperConvException;
        auto ret = allocator.makeArray!char(numChars);

        if(ret is null && numChars > 0)
            throw fromXlOperMemoryException;

        ret[] = buffer[0 .. numChars];
        return cast(string)ret;
    }
}

@("fromXlOper!string missing")
@system unittest {
    import xlld.memorymanager: allocator;
    XLOPER12 oper;
    oper.xltype = XlType.xltypeMissing;
    fromXlOper!string(&oper, allocator).shouldBeNull;
}

@("fromXlOper!string")
@system unittest {
    import std.experimental.allocator: dispose;
    TestAllocator allocator;
    auto oper = "foo".toXlOper(allocator);
    auto str = fromXlOper!string(&oper, allocator);
    allocator.numAllocations.shouldEqual(2);

    freeXLOper(&oper, allocator);
    str.shouldEqual("foo");
    allocator.dispose(cast(void[])str);
}

@("fromXlOper!string unicode")
@system unittest {
    auto oper = "é".toXlOper(theGC);
    auto str = fromXlOper!string(&oper, theGC);
    str.shouldEqual("é");
}

package XlType stripMemoryBitmask(in XlType type) @safe @nogc pure nothrow {
    return cast(XlType)(type & ~(xlbitXLFree | xlbitDLLFree));
}

T fromXlOper(T, A)(LPXLOPER12 oper, ref A allocator) if(is(T == Any)) {
    // FIXME: deep copy
    return Any(*oper);
}

@("fromXlOper any double")
@system unittest {
    any(5.0, theMallocator).fromXlOper!Any(theMallocator).shouldEqual(any(5.0, theMallocator));
}

@("fromXlOper any string")
@system unittest {
    any("foo", theMallocator).fromXlOper!Any(theMallocator)._impl
        .fromXlOper!string(theMallocator).shouldEqual("foo");
}

auto fromXlOper(T, A)(LPXLOPER12 val, ref A allocator)
    if(is(T: E[][], E) && (is(E == string) || is(E == double)))
{
    return val.fromXlOperMulti!(Dimensions.Two, typeof(T.init[0][0]))(allocator);
}

@("fromXlOper!string[][]")
unittest {
    import xlld.memorymanager: allocator;

    auto strings = [["foo", "bar", "baz"], ["toto", "titi", "quux"]];
    auto oper = strings.toXlOper(allocator);
    scope(exit) freeXLOper(&oper, allocator);
    oper.fromXlOper!(string[][])(allocator).shouldEqual(strings);
}

@("fromXlOper!double[][]")
unittest {
    import xlld.memorymanager: allocator;

    auto doubles = [[1.0, 2.0], [3.0, 4.0]];
    auto oper = doubles.toXlOper(allocator);
    scope(exit) freeXLOper(&oper, allocator);
    oper.fromXlOper!(double[][])(allocator).shouldEqual(doubles);
}

@("fromXlOper!string[][] TestAllocator")
unittest {
    import std.experimental.allocator: disposeMultidimensionalArray;
    TestAllocator allocator;
    auto strings = [["foo", "bar", "baz"], ["toto", "titi", "quux"]];
    auto oper = strings.toXlOper(allocator);
    auto backAgain = oper.fromXlOper!(string[][])(allocator);

    allocator.numAllocations.shouldEqual(16);

    freeXLOper(&oper, allocator);
    backAgain.shouldEqual(strings);
    allocator.disposeMultidimensionalArray(cast(void[][][])backAgain);
}

@("fromXlOper!string[][] when not all opers are strings")
unittest {
    import std.experimental.allocator.mallocator: Mallocator;
    alias allocator = Mallocator.instance;

    const rows = 2;
    const cols = 3;
    auto array = multi(rows, cols, allocator);
    auto opers = array.val.array.lparray[0 .. rows*cols];
    const strings = ["foo", "bar", "baz"];
    const numbers = [1.0, 2.0, 3.0];

    int i;
    foreach(r; 0 .. rows) {
        foreach(c; 0 .. cols) {
            if(r == 0)
                opers[i++] = strings[c].toXlOper(allocator);
            else
                opers[i++] = numbers[c].toXlOper(allocator);
        }
    }

    opers[3].fromXlOper!string(allocator).shouldEqual("1.000000");
    // sanity checks
    opers[0].fromXlOper!string(allocator).shouldEqual("foo");
    opers[3].fromXlOper!double(allocator).shouldEqual(1.0);
    // the actual assertion
    array.fromXlOper!(string[][])(allocator).shouldEqual([["foo", "bar", "baz"],
                                                          ["1.000000", "2.000000", "3.000000"]]);
}


@("fromXlOper!double[][] TestAllocator")
unittest {
    import std.experimental.allocator: disposeMultidimensionalArray;
    TestAllocator allocator;
    auto doubles = [[1.0, 2.0], [3.0, 4.0]];
    auto oper = doubles.toXlOper(allocator);
    auto backAgain = oper.fromXlOper!(double[][])(allocator);

    allocator.numAllocations.shouldEqual(4);

    freeXLOper(&oper, allocator);
    backAgain.shouldEqual(doubles);
    allocator.disposeMultidimensionalArray(backAgain);
}


private enum Dimensions {
    One,
    Two,
}


// 1D slices
auto fromXlOper(T, A)(LPXLOPER12 val, ref A allocator)
    if(is(T: E[], E) && (is(E == string) || is(E == double)))
{
    return val.fromXlOperMulti!(Dimensions.One, typeof(T.init[0]))(allocator);
}


@("fromXlOper!string[]")
unittest {
    import xlld.memorymanager: allocator;

    auto strings = ["foo", "bar", "baz", "toto", "titi", "quux"];
    auto oper = strings.toXlOper(allocator);
    scope(exit) freeXLOper(&oper, allocator);
    oper.fromXlOper!(string[])(allocator).shouldEqual(strings);
}

@("fromXlOper!double[]")
unittest {
    import xlld.memorymanager: allocator;

    auto doubles = [1.0, 2.0, 3.0, 4.0];
    auto oper = doubles.toXlOper(allocator);
    scope(exit) freeXLOper(&oper, allocator);
    oper.fromXlOper!(double[])(allocator).shouldEqual(doubles);
}

@("fromXlOper!string[] TestAllocator")
unittest {
    import std.experimental.allocator: disposeMultidimensionalArray;
    TestAllocator allocator;
    auto strings = ["foo", "bar", "baz", "toto", "titi", "quux"];
    auto oper = strings.toXlOper(allocator);
    auto backAgain = oper.fromXlOper!(string[])(allocator);

    allocator.numAllocations.shouldEqual(14);

    backAgain.shouldEqual(strings);
    freeXLOper(&oper, allocator);
    allocator.disposeMultidimensionalArray(cast(void[][])backAgain);
}

@("fromXlOper!double[] TestAllocator")
unittest {
    import std.experimental.allocator: dispose;
    TestAllocator allocator;
    auto doubles = [1.0, 2.0, 3.0, 4.0];
    auto oper = doubles.toXlOper(allocator);
    auto backAgain = oper.fromXlOper!(double[])(allocator);

    allocator.numAllocations.shouldEqual(2);

    backAgain.shouldEqual(doubles);
    freeXLOper(&oper, allocator);
    allocator.dispose(backAgain);
}

__gshared immutable fromXlOperMultiOperException = new Exception("oper not of multi type");
__gshared immutable fromXlOperMultiMemoryException = new Exception("Could not allocate memory in fromXlOperMulti");

private auto fromXlOperMulti(Dimensions dim, T, A)(LPXLOPER12 val, ref A allocator) {
    import xlld.xl: coerce, free;
    import xlld.memorymanager: makeArray2D;
    import std.experimental.allocator: makeArray;

    if(!isMulti(*val)) {
        throw fromXlOperMultiOperException;
    }

    const rows = val.val.array.rows;
    const cols = val.val.array.columns;

    assert(rows > 0 && cols > 0, "Multi opers may not have 0 rows or columns");

    static if(dim == Dimensions.Two) {
        auto ret = allocator.makeArray2D!T(*val);
    } else static if(dim == Dimensions.One) {
        auto ret = allocator.makeArray!T(rows * cols);
    } else
        static assert(0, "Unknown number of dimensions in fromXlOperMulti");

    if(&ret[0] is null)
        throw fromXlOperMultiMemoryException;

    (*val).apply!(T, (shouldConvert, row, col, cellVal) {

        auto value = shouldConvert ? cellVal.fromXlOper!T(allocator) : T.init;

        static if(dim == Dimensions.Two)
            ret[row][col] = value;
        else
            ret[row * cols + col] = value;
    });

    return ret;
}

__gshared immutable applyTypeException = new Exception("apply failed - oper not of multi type");

// apply a function to an oper of type xltypeMulti
// the function must take a boolean value indicating if the cell value
// is to be converted or not, and a reference to the cell value itself
package void apply(T, alias F)(ref XLOPER12 oper) {
    import xlld.xlcall: XlType;
    import xlld.xl: coerce, free;
    import xlld.wrap: dlangToXlOperType, isMulti, numOperStringBytes;
    import xlld.any: Any;
    version(unittest) import xlld.test_util: gNumXlCoerce, gNumXlFree;

    if(!isMulti(oper))
        throw applyTypeException;

    const rows = oper.val.array.rows;
    const cols = oper.val.array.columns;
    auto values = oper.val.array.lparray[0 .. (rows * cols)];

    foreach(const row; 0 .. rows) {
        foreach(const col; 0 .. cols) {

            auto cellVal = coerce(&values[row * cols + col]);

            // Issue 22's unittest ends up coercing more than test_util can handle
            // so we undo the side-effect here
            version(unittest) --gNumXlCoerce; // ignore this for testing

            scope(exit) {
                free(&cellVal);
                // see comment above about gNumXlCoerce
                version(unittest) --gNumXlFree;
            }

            // try to convert doubles to string if trying to convert everything to an
            // array of strings
            const shouldConvert =
                (cellVal.xltype == dlangToXlOperType!T.Type) ||
                (cellVal.xltype == XlType.xltypeNum && dlangToXlOperType!T.Type == XlType.xltypeStr) ||
                is(T == Any);

            F(shouldConvert, row, col, cellVal);
        }
    }
}


package bool isMulti(ref const(XLOPER12) oper) @safe @nogc pure nothrow {
    const realType = stripMemoryBitmask(oper.xltype);
    return realType == XlType.xltypeMulti;
}


T fromXlOper(T, A)(LPXLOPER12 oper, ref A allocator) if(is(T == Any[])) {
    return oper.fromXlOperMulti!(Dimensions.One, Any)(allocator);
}


@("fromXlOper any 1D array")
@system unittest {
    import xlld.memorymanager: allocatorContext;
    with(allocatorContext(theMallocator)) {
        auto array = [any(1.0), any("foo")];
        auto oper = toXlOper(array);
        auto back = fromXlOper!(Any[])(oper);
        back.shouldEqual(array);
    }
}


T fromXlOper(T, A)(LPXLOPER12 oper, ref A allocator) if(is(T == Any[][])) {
    return oper.fromXlOperMulti!(Dimensions.Two, typeof(T.init[0][0]))(allocator);
}


@("fromXlOper Any 2D array")
@system unittest {
    import xlld.memorymanager: allocatorContext;
    with(allocatorContext(theMallocator)) {
        auto array = [[any(1.0), any(2.0)], [any("foo"), any("bar")]];
        auto oper = toXlOper(array);
        auto back = fromXlOper!(Any[][])(oper);
        back.shouldEqual(array);
    }
}


private enum isWorksheetFunction(alias F) =
    isSupportedFunction!(F, double, double[][], string[][], string[], double[], string, Any, Any[], Any[][], int);

@safe pure unittest {
    import xlld.test_d_funcs;
    // the line below checks that the code still compiles even with a private function
    // it might stop compiling in a future version when the deprecation rules for
    // visibility kick in
    static assert(!isWorksheetFunction!shouldNotBeAProblem);
    static assert(!isWorksheetFunction!FuncThrows);
    static assert(isWorksheetFunction!DoubleArrayToAnyArray);
    static assert(isWorksheetFunction!Twice);
}

/**
   A string to mixin that wraps all eligible functions in the
   given module.
 */
string wrapModuleWorksheetFunctionsString(string moduleName)() {
    if(!__ctfe) {
        return "";
    }

    import xlld.traits: Identity;
    import std.array: join;
    import std.traits: ReturnType, Parameters;

    mixin(`import ` ~ moduleName ~ `;`);
    alias module_ = Identity!(mixin(moduleName));

    string ret = `static import ` ~ moduleName ~ ";\n\n";

    foreach(moduleMemberStr; __traits(allMembers, module_)) {
        alias moduleMember = Identity!(__traits(getMember, module_, moduleMemberStr));

        static if(isWorksheetFunction!moduleMember) {
            ret ~= wrapModuleFunctionStr!(moduleName, moduleMemberStr);
        }
    }

    return ret;
}


@("Wrap double[][] -> double")
@system unittest {
    import xlld.memorymanager: allocator;

    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");

    auto arg = toSRef(cast(double[][])[[1, 2, 3, 4], [11, 12, 13, 14]], allocator);
    FuncAddEverything(&arg).shouldEqualDlang(60.0);

    arg = toSRef(cast(double[][])[[0, 1, 2, 3], [4, 5, 6, 7]], allocator);
    FuncAddEverything(&arg).shouldEqualDlang(28.0);
}

@("Wrap double[][] -> double[][]")
@system unittest {
    import xlld.memorymanager: allocator;

    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");

    auto arg = toSRef(cast(double[][])[[1, 2, 3, 4], [11, 12, 13, 14]], allocator);
    FuncTripleEverything(&arg).shouldEqualDlang(cast(double[][])[[3, 6, 9, 12], [33, 36, 39, 42]]);

    arg = toSRef(cast(double[][])[[0, 1, 2, 3], [4, 5, 6, 7]], allocator);
    FuncTripleEverything(&arg).shouldEqualDlang(cast(double[][])[[0, 3, 6, 9], [12, 15, 18, 21]]);
}


@("Wrap string[][] -> double")
@system unittest {

    import xlld.memorymanager: allocator;

    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");

    auto arg = toSRef([["foo", "bar", "baz", "quux"], ["toto", "titi", "tutu", "tete"]], allocator);
    FuncAllLengths(&arg).shouldEqualDlang(29.0);

    arg = toSRef([["", "", "", ""], ["", "", "", ""]], allocator);
    FuncAllLengths(&arg).shouldEqualDlang(0.0);
}

@("Wrap string[][] -> double[][]")
@system unittest {

    import xlld.memorymanager: allocator;

    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");

    auto arg = toSRef([["foo", "bar", "baz", "quux"], ["toto", "titi", "tutu", "tete"]], allocator);
    FuncLengths(&arg).shouldEqualDlang(cast(double[][])[[3, 3, 3, 4], [4, 4, 4, 4]]);

    arg = toSRef([["", "", ""], ["", "", "huh"]], allocator);
    FuncLengths(&arg).shouldEqualDlang(cast(double[][])[[0, 0, 0], [0, 0, 3]]);
}

@("Wrap string[][] -> string[][]")
@system unittest {

    import xlld.memorymanager: allocator;

    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");

    auto arg = toSRef([["foo", "bar", "baz", "quux"], ["toto", "titi", "tutu", "tete"]], allocator);
    FuncBob(&arg).shouldEqualDlang([["foobob", "barbob", "bazbob", "quuxbob"],
                                    ["totobob", "titibob", "tutubob", "tetebob"]]);
}

@("Wrap string[] -> double")
@system unittest {
    import xlld.memorymanager: allocator;

    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toSRef([["foo", "bar"], ["baz", "quux"]], allocator);
    FuncStringSlice(&arg).shouldEqualDlang(4.0);
}

@("Wrap double[] -> double")
@system unittest {
    import xlld.memorymanager: allocator;
    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toSRef([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], allocator);
    FuncDoubleSlice(&arg).shouldEqualDlang(6.0);
}

@("Wrap double[] -> double[]")
@system unittest {
    import xlld.memorymanager: allocator;
    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toSRef([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], allocator);
    FuncSliceTimes3(&arg).shouldEqualDlang([3.0, 6.0, 9.0, 12.0, 15.0, 18.0]);
}

@("Wrap string[] -> string[]")
@system unittest {
    import xlld.memorymanager: allocator;
    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toSRef(["quux", "toto"], allocator);
    StringsToStrings(&arg).shouldEqualDlang(["quuxfoo", "totofoo"]);
}

@("Wrap string[] -> string")
@system unittest {
    import xlld.memorymanager: allocator;
    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toSRef(["quux", "toto"], allocator);
    StringsToString(&arg).shouldEqualDlang("quux, toto");
}

@("Wrap string -> string")
@system unittest {
    import xlld.memorymanager: allocator;
    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toXlOper("foo", allocator);
    StringToString(&arg).shouldEqualDlang("foobar");
}

@("Wrap string, string, string -> string")
@system unittest {
    import xlld.memorymanager: allocator;
    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg0 = toXlOper("foo", allocator);
    auto arg1 = toXlOper("bar", allocator);
    auto arg2 = toXlOper("baz", allocator);
    ManyToString(&arg0, &arg1, &arg2).shouldEqualDlang("foobarbaz");
}

@("Only look at nothrow functions")
@system unittest {
    import xlld.memorymanager: allocator;
    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toXlOper(2.0, allocator);
    static assert(!__traits(compiles, FuncThrows(&arg)));
}

@("FuncAddEverything wrapper is @nogc")
@system @nogc unittest {
    import std.experimental.allocator.mallocator: Mallocator;
    import xlld.framework: freeXLOper;

    mixin(wrapModuleWorksheetFunctionsString!"xlld.test_d_funcs");
    auto arg = toXlOper(2.0, Mallocator.instance);
    scope(exit) freeXLOper(&arg, Mallocator.instance);
    FuncAddEverything(&arg);
}

private enum invalidXlOperType = 0xdeadbeef;

/**
 Maps a D type to two integer xltypes from XLOPER12.
 InputType is the type actually passed in by the spreadsheet,
 whilst Type is the Type that it gets coerced to.
 */
template dlangToXlOperType(T) {
    static if(is(T == double[][]) || is(T == string[][]) || is(T == double[]) || is(T == string[])) {
        enum InputType = XlType.xltypeSRef;
        enum Type = XlType.xltypeMulti;
    } else static if(is(T == double)) {
        enum InputType = XlType.xltypeNum;
        enum Type = XlType.xltypeNum;
    } else static if(is(T == string)) {
        enum InputType = XlType.xltypeStr;
        enum Type = XlType.xltypeStr;
    } else {
        enum InputType = invalidXlOperType;
        enum Type = invalidXlOperType;
    }
}

/**
 A string to use with `mixin` that wraps a D function
 */
string wrapModuleFunctionStr(string moduleName, string funcName)() {
    if(!__ctfe) {
        return "";
    }

    import std.array: join;
    import std.traits: Parameters, functionAttributes, FunctionAttribute, getUDAs;
    import std.conv: to;
    import std.algorithm: map;
    import std.range: iota;
    import std.format: format;

    mixin("import " ~ moduleName ~ ": " ~ funcName ~ ";");

    const argsLength = Parameters!(mixin(funcName)).length;
    // e.g. LPXLOPER12 arg0, LPXLOPER12 arg1, ...
    const argsDecl = argsLength.iota.map!(a => `LPXLOPER12 arg` ~ a.to!string).join(", ");
    // e.g. arg0, arg1, ...
    const argsCall = argsLength.iota.map!(a => `arg` ~ a.to!string).join(", ");
    const nogc = functionAttributes!(mixin(funcName)) & FunctionAttribute.nogc
        ? "@nogc "
        : "";
    const safe = functionAttributes!(mixin(funcName)) & FunctionAttribute.safe
        ? "@trusted "
        : "";

    alias registerAttrs = getUDAs!(mixin(funcName), Register);
    static assert(registerAttrs.length == 0 || registerAttrs.length == 1,
                  "Invalid number of @Register on " ~ funcName);

    string register;
    static if(registerAttrs.length)
        register = `@` ~ registerAttrs[0].to!string;

    return [
        register,
        q{
            extern(Windows) LPXLOPER12 %s(%s) nothrow %s %s {
                static import %s;
                import xlld.memorymanager: gTempAllocator;
                alias wrappedFunc = %s.%s;
                return wrapModuleFunctionImpl!wrappedFunc(gTempAllocator, %s);
            }
        }.format(funcName, argsDecl, nogc, safe, moduleName, moduleName, funcName, argsCall),
    ].join("\n");
}

@system unittest {
    import xlld.worksheet;
    import std.traits: getUDAs;

    mixin(wrapModuleFunctionStr!("xlld.test_d_funcs", "FuncAddEverything"));
    alias registerAttrs = getUDAs!(FuncAddEverything, Register);
    static assert(registerAttrs[0].argumentText.value == "Array to add");
}

/**
 Implement a wrapper for a regular D function
 */
LPXLOPER12 wrapModuleFunctionImpl(alias wrappedFunc, A, T...)
                                  (ref A tempAllocator, auto ref T args) {
    import xlld.xl: coerce, free;
    import xlld.worksheet: Dispose;
    import std.traits: Parameters;
    import std.typecons: Tuple;
    import std.traits: hasUDA, getUDAs;

    static XLOPER12 ret;

    XLOPER12[T.length] realArgs;

    // must 1st convert each argument to the "real" type.
    // 2D arrays are passed in as SRefs, for instance
    foreach(i, InputType; Parameters!wrappedFunc) {
        if(args[i].xltype == xltypeMissing) {
             realArgs[i] = *args[i];
             continue;
        }
        realArgs[i] = coerce(args[i]);
    }

    // scopedCoerce doesn't work with actual Excel
    scope(exit) {
        foreach(ref arg; realArgs)
            free(&arg);
    }

    Tuple!(Parameters!wrappedFunc) dArgs; // the D types to pass to the wrapped function

    void setRetToError(in string msg) {
        try
            ret = msg.toAutoFreeOper;
        catch(Exception _) {
            ret.xltype = XlType.xltypeErr;
        }
    }

    void freeAll() {
        static if(__traits(compiles, tempAllocator.deallocateAll))
            tempAllocator.deallocateAll;
        else {
            foreach(ref dArg; dArgs) {
                import std.traits: isPointer, isArray;
                static if(isArray!(typeof(dArg)))
                {
                    import std.experimental.allocator: disposeMultidimensionalArray;
                    tempAllocator.disposeMultidimensionalArray(dArg[]);
                }
                else
                static if(isPointer!(typeof(dArg)))
                {
                    import std.experimental.allocator: dispose;
                    tempAllocator.dispose(dArg);
                }
            }
        }
    }

    // get rid of the temporary memory allocations for the conversions
    scope(exit) freeAll;

    // convert all Excel types to D types
    foreach(i, InputType; Parameters!wrappedFunc) {
        try {
            dArgs[i] = () @trusted { return fromXlOper!InputType(&realArgs[i], tempAllocator); }();
        } catch(Exception ex) {
            setRetToError("#ERROR converting argument to call " ~ __traits(identifier, wrappedFunc));
            return &ret;
        } catch(Throwable t) {
            setRetToError("#FATAL ERROR converting argument to call " ~ __traits(identifier, wrappedFunc));
            return &ret;
        }
    }

    try {

        // call the wrapped function with D types
        auto wrappedRet = wrappedFunc(dArgs.expand);
        ret = excelRet(wrappedRet);

        // dispose of the memory allocated in the wrapped function
        static if(hasUDA!(wrappedFunc, Dispose)) {
            alias disposes = getUDAs!(wrappedFunc, Dispose);
            static assert(disposes.length == 1, "Too many @Dispose for " ~ wrappedFunc.stringof);
            disposes[0].dispose(wrappedRet);
        }

    } catch(Exception ex) {

        version(unittest) {
            import core.stdc.stdio: printf;
            static char[1024] buffer;
            buffer[0 .. ex.msg.length] = ex.msg[];
            buffer[ex.msg.length + 1] = 0;
            () @trusted { printf("Could not call wrapped function: %s\n", &buffer[0]); }();
        }

        setRetToError("#ERROR calling " ~ __traits(identifier, wrappedFunc));
        return &ret;
    } catch(Throwable t) {
        setRetToError("#FATAL ERROR calling " ~ __traits(identifier, wrappedFunc));
        return &ret;
    }

    return &ret;
}

// get excel return value from D return value of wrapped function
private XLOPER12 excelRet(T)(T wrappedRet) {

    import std.traits: isArray;

    // Excel crashes if it's returned an empty array, so stop that from happening
    static if(isArray!(typeof(wrappedRet))) {
        if(wrappedRet.length == 0) {
            return "#ERROR: empty result".toAutoFreeOper;
        }

        static if(isArray!(typeof(wrappedRet[0]))) {
            if(wrappedRet[0].length == 0) {
                return "#ERROR: empty result".toAutoFreeOper;
            }
        }
    }

    // convert the return value to an Excel type, tell Excel to call
    // us back to free it afterwards
    return toAutoFreeOper(wrappedRet);
}

@("No memory allocation bugs in wrapModuleFunctionImpl for double return Mallocator")
@system unittest {
    import std.experimental.allocator.mallocator: Mallocator;
    import xlld.test_d_funcs: FuncAddEverything;

    TestAllocator allocator;
    auto arg = toSRef([1.0, 2.0], Mallocator.instance);
    auto oper = wrapModuleFunctionImpl!FuncAddEverything(allocator, &arg);
    (oper.xltype & xlbitDLLFree).shouldBeTrue;
    allocator.numAllocations.shouldEqual(2);
    oper.shouldEqualDlang(3.0);
    autoFree(oper); // normally this is done by Excel
}

@("No memory allocation bugs in wrapModuleFunctionImpl for double[][] return Mallocator")
@system unittest {
    import std.experimental.allocator.mallocator: Mallocator;
    import xlld.test_d_funcs: FuncTripleEverything;

    TestAllocator allocator;
    auto arg = toSRef([1.0, 2.0, 3.0], Mallocator.instance);
    auto oper = wrapModuleFunctionImpl!FuncTripleEverything(allocator, &arg);
    (oper.xltype & xlbitDLLFree).shouldBeTrue;
    (oper.xltype & ~xlbitDLLFree).shouldEqual(xltypeMulti);
    allocator.numAllocations.shouldEqual(2);
    oper.shouldEqualDlang([[3.0, 6.0, 9.0]]);
    autoFree(oper); // normally this is done by Excel
}

@("No memory allocation bugs in wrapModuleFunctionImpl for double[][] return pool")
@system unittest {
    import std.typecons: Ternary;
    import xlld.memorymanager: gTempAllocator;
    import xlld.test_d_funcs: FuncTripleEverything;

    auto arg = toSRef([1.0, 2.0, 3.0], gTempAllocator);
    auto oper = wrapModuleFunctionImpl!FuncTripleEverything(gTempAllocator, &arg);
    gTempAllocator.empty.shouldEqual(Ternary.yes);
    oper.shouldEqualDlang([[3.0, 6.0, 9.0]]);
    autoFree(oper); // normally this is done by Excel
}

@("No memory allocation bugs in wrapModuleFunctionImpl for string")
@system unittest {
    import std.typecons: Ternary;
    import xlld.memorymanager: gTempAllocator;
    import xlld.test_d_funcs: StringToString;

    auto arg = "foo".toSRef(gTempAllocator);
    auto oper = wrapModuleFunctionImpl!StringToString(gTempAllocator, &arg);
    gTempAllocator.empty.shouldEqual(Ternary.yes);
    oper.shouldEqualDlang("foobar");
}

@("No memory allocation bugs in wrapModuleFunctionImpl for Any[][] -> Any[][] -> Any[][] mallocator")
@system unittest {
    import xlld.memorymanager: allocatorContext;
    import xlld.test_d_funcs: FirstOfTwoAnyArrays;

    with(allocatorContext(theGC)) {
        auto dArg = [[any(1.0), any("foo"), any(3.0)], [any(4.0), any(5.0), any(6.0)]];
        auto arg = toXlOper(dArg);
        auto oper = wrapModuleFunctionImpl!FirstOfTwoAnyArrays(theMallocator, &arg, &arg);
        oper.shouldEqualDlang(dArg);
    }
}

@("No memory allocation bugs in wrapModuleFunctionImpl for Any[][] -> Any[][] -> Any[][] TestAllocator")
@system unittest {
    import xlld.memorymanager: allocatorContext;
    import xlld.test_d_funcs: FirstOfTwoAnyArrays;

    auto testAllocator = TestAllocator();

    with(allocatorContext(theGC)) {
        auto dArg = [[any(1.0), any("foo"), any(3.0)], [any(4.0), any(5.0), any(6.0)]];
        auto arg = toXlOper(dArg);
        auto oper = wrapModuleFunctionImpl!FirstOfTwoAnyArrays(testAllocator, &arg, &arg);
        oper.shouldEqualDlang(dArg);
    }
}

@("Correct number of coercions and frees in wrapModuleFunctionImpl")
@system unittest {
    import xlld.test_d_funcs: FuncAddEverything;
    import xlld.test_util: gNumXlCoerce, gNumXlFree;

    const oldNumCoerce = gNumXlCoerce;
    const oldNumFree = gNumXlFree;

    auto arg = toSRef([1.0, 2.0], theGC);
    auto oper = wrapModuleFunctionImpl!FuncAddEverything(theGC, &arg);

    (gNumXlCoerce - oldNumCoerce).shouldEqual(1);
    (gNumXlFree   - oldNumFree).shouldEqual(1);
}


@("Can't return empty 1D array to Excel")
@system unittest {
    import xlld.memorymanager: allocatorContext;
    import xlld.test_d_funcs: EmptyStrings1D;

    with(allocatorContext(theGC)) {
        auto dArg = any(1.0);
        auto arg = toXlOper(dArg);
        auto oper = wrapModuleFunctionImpl!EmptyStrings1D(theGC, &arg);
        oper.shouldEqualDlang("#ERROR: empty result");
    }
}


@("Can't return empty 2D array to Excel")
@system unittest {
    import xlld.memorymanager: allocatorContext;
    import xlld.test_d_funcs: EmptyStrings2D;

    with(allocatorContext(theGC)) {
        auto dArg = any(1.0);
        auto arg = toXlOper(dArg);
        auto oper = wrapModuleFunctionImpl!EmptyStrings2D(theGC, &arg);
        oper.shouldEqualDlang("#ERROR: empty result");
    }
}

@("Can't return half empty 2D array to Excel")
@system unittest {
    import xlld.memorymanager: allocatorContext;
    import xlld.test_d_funcs: EmptyStringsHalfEmpty2D;

    with(allocatorContext(theGC)) {
        auto dArg = any(1.0);
        auto arg = toXlOper(dArg);
        auto oper = wrapModuleFunctionImpl!EmptyStringsHalfEmpty2D(theGC, &arg);
        oper.shouldEqualDlang("#ERROR: empty result");
    }
}

@("issue 25 - make sure to reserve memory for all dArgs")
@system unittest {
    import std.typecons: Ternary;
    import xlld.memorymanager: allocatorContext, MemoryPool;
    import xlld.test_d_funcs: FirstOfTwoAnyArrays;

    auto pool = MemoryPool();

    with(allocatorContext(theGC)) {
        auto dArg = [[any(1.0), any("foo"), any(3.0)], [any(4.0), any(5.0), any(6.0)]];
        auto arg = toSRef(dArg);
        auto oper = wrapModuleFunctionImpl!FirstOfTwoAnyArrays(pool, &arg, &arg);
    }

    pool.empty.shouldEqual(Ternary.yes); // deallocateAll in wrapImpl
}

string wrapWorksheetFunctionsString(Modules...)() {

    if(!__ctfe) {
        return "";
    }

    string ret;
    foreach(module_; Modules) {
        ret ~= wrapModuleWorksheetFunctionsString!module_;
    }

    return ret;
}


string wrapAll(Modules...)(in string mainModule = __MODULE__) {

    if(!__ctfe) {
        return "";
    }

    import xlld.traits: implGetWorksheetFunctionsString;
    return
        wrapWorksheetFunctionsString!Modules ~
        "\n" ~
        implGetWorksheetFunctionsString!(mainModule) ~
        "\n" ~
        `mixin GenerateDllDef!"` ~ mainModule ~ `";` ~
        "\n";
}

@("wrapAll")
unittest  {
    import xlld.memorymanager: allocator;
    import xlld.traits: getAllWorksheetFunctions, GenerateDllDef; // for wrapAll

    mixin(wrapAll!("xlld.test_d_funcs"));
    auto arg = toSRef(cast(double[][])[[1, 2, 3, 4], [11, 12, 13, 14]], allocator);
    FuncAddEverything(&arg).shouldEqualDlang(60.0);
}


/**
  creates an XLOPER12 that can be returned to Excel which
  will be freed by Excel itself
 */
XLOPER12 toAutoFreeOper(T)(T value) {
    import xlld.memorymanager: autoFreeAllocator;
    import xlld.xlcall: XlType;

    auto result = value.toXlOper(autoFreeAllocator);
    result.xltype |= XlType.xlbitDLLFree;
    return result;
}

ushort operStringLength(T)(in T value) {
    import nogc.exception: enforce;

    enforce(value.xltype == XlType.xltypeStr,
            "Cannot calculate string length for oper of type ", value.xltype);

    return cast(ushort)value.val.str[0];
}

@("operStringLength")
unittest {
    import std.experimental.allocator.mallocator: Mallocator;
    auto oper = "foobar".toXlOper(Mallocator.instance);
    const length = () @nogc { return operStringLength(oper); }();
    length.shouldEqual(6);
}

auto fromXlOperCoerce(T)(LPXLOPER12 val) {
    return fromXlOperCoerce(*val);
}

auto fromXlOperCoerce(T, A)(LPXLOPER12 val, auto ref A allocator) {
    return fromXlOperCoerce!T(*val, allocator);
}


auto fromXlOperCoerce(T)(ref XLOPER12 val) {
    import xlld.memorymanager: allocator;
    return fromXlOperCoerce!T(val, allocator);
}


auto fromXlOperCoerce(T, A)(ref XLOPER12 val, auto ref A allocator) {
    import xlld.xl: coerce, free;

    auto coerced = coerce(&val);
    scope(exit) free(&coerced);

    return coerced.fromXlOper!T(allocator);
}


@("fromXlOperCoerce")
unittest {
    double[][] doubles = [[1, 2, 3, 4], [11, 12, 13, 14]];
    auto doublesOper = toSRef(doubles, theGC);
    doublesOper.fromXlOper!(double[][])(theGC).shouldThrowWithMessage(
        "oper not of multi type");
    doublesOper.fromXlOperCoerce!(double[][]).shouldEqual(doubles);
}

@("wrap function with @Dispose")
@safe unittest {
    import xlld.test_util: gTestAllocator;
    import xlld.memorymanager: gTempAllocator;
    import xlld.traits: getAllWorksheetFunctions, GenerateDllDef; // for wrapAll

    // this is needed since gTestAllocator is global, so we can't rely
    // on its destructor
    scope(exit) gTestAllocator.verify;

    mixin(wrapAll!("xlld.test_d_funcs"));
    double[4] args = [1.0, 2.0, 3.0, 4.0];
    auto oper = args[].toSRef(gTempAllocator); // don't use TestAllocator
    auto arg = () @trusted { return &oper; }();
    auto ret = () @safe @nogc { return FuncReturnArrayNoGc(arg); }();
    ret.shouldEqualDlang([2.0, 4.0, 6.0, 8.0]);
}

@("wrapModuleFunctionStr function that returns Any[][]")
@safe unittest {
    mixin(wrapModuleFunctionStr!("xlld.test_d_funcs", "DoubleArrayToAnyArray"));

    auto oper = [[1.0, 2.0], [3.0, 4.0]].toSRef(theMallocator);
    auto arg = () @trusted { return &oper; }();
    auto ret = DoubleArrayToAnyArray(arg);

    auto opers = () @trusted { return ret.val.array.lparray[0 .. 4]; }();
    opers[0].shouldEqualDlang(2.0);
    opers[1].shouldEqualDlang(6.0);
    opers[2].shouldEqualDlang("3quux");
    opers[3].shouldEqualDlang("4toto");
}

@("wrapModuleFunctionStr int -> int")
@safe unittest {
    mixin(wrapModuleFunctionStr!("xlld.test_d_funcs", "Twice"));

    auto oper = 3.toSRef(theGC);
    auto arg = () @trusted { return &oper; }();
    Twice(arg).shouldEqualDlang(6);
}


@("wrapAll function that returns Any[][]")
@safe unittest {
    import xlld.traits: getAllWorksheetFunctions, GenerateDllDef; // for wrapAll

    mixin(wrapAll!("xlld.test_d_funcs"));

    auto oper = [[1.0, 2.0], [3.0, 4.0]].toSRef(theMallocator);
    auto arg = () @trusted { return &oper; }();
    auto ret = DoubleArrayToAnyArray(arg);
    scope(exit) () @trusted { autoFree(ret); }(); // usually done by Excel

    auto opers = () @trusted { return ret.val.array.lparray[0 .. 4]; }();
    opers[0].shouldEqualDlang(2.0);
    opers[1].shouldEqualDlang(6.0);
    opers[2].shouldEqualDlang("3quux");
    opers[3].shouldEqualDlang("4toto");
}

@("wrapAll function that takes Any[][]")
unittest {
    import xlld.traits: getAllWorksheetFunctions, GenerateDllDef; // for wrapAll
    import xlld.memorymanager: allocatorContext;

    mixin(wrapAll!("xlld.test_d_funcs"));

    LPXLOPER12 ret;
    with(allocatorContext(theMallocator)) {
        auto oper = [[any(1.0), any(2.0)], [any(3.0), any(4.0)], [any("foo"), any("bar")]].toXlOper(theMallocator);
        auto arg = () @trusted { return &oper; }();
        ret = AnyArrayToDoubleArray(arg);
    }

    auto opers = () @trusted { return ret.val.array.lparray[0 .. 2]; }();
    opers[0].shouldEqualDlang(3.0); // number of rows
    opers[1].shouldEqualDlang(2.0); // number of columns
}


@("wrapAll Any[][] -> Any[][]")
unittest {
    import xlld.traits: getAllWorksheetFunctions, GenerateDllDef; // for wrapAll
    import xlld.memorymanager: allocatorContext;
    import xlld.any: Any;

    mixin(wrapAll!("xlld.test_d_funcs"));

    LPXLOPER12 ret;
    with(allocatorContext(theMallocator)) {
        auto oper = [[any(1.0), any(2.0)], [any(3.0), any(4.0)], [any("foo"), any("bar")]].toXlOper(theMallocator);
        auto arg = () @trusted { return &oper; }();
        ret = AnyArrayToAnyArray(arg);
    }

    auto opers = () @trusted { return ret.val.array.lparray[0 .. 6]; }();
    ret.val.array.rows.shouldEqual(3);
    ret.val.array.columns.shouldEqual(2);
    opers[0].shouldEqualDlang(1.0);
    opers[1].shouldEqualDlang(2.0);
    opers[2].shouldEqualDlang(3.0);
    opers[3].shouldEqualDlang(4.0);
    opers[4].shouldEqualDlang("foo");
    opers[5].shouldEqualDlang("bar");
}

@("wrapAll Any[][] -> Any[][] -> Any[][]")
unittest {
    import xlld.traits: getAllWorksheetFunctions, GenerateDllDef; // for wrapAll
    import xlld.memorymanager: allocatorContext;
    import xlld.any: Any;

    mixin(wrapAll!("xlld.test_d_funcs"));

    LPXLOPER12 ret;
    with(allocatorContext(theMallocator)) {
        auto oper = [[any(1.0), any("foo"), any(3.0)], [any(4.0), any(5.0), any(6.0)]].toXlOper(theMallocator);
        auto arg = () @trusted { return &oper; }();
        ret = FirstOfTwoAnyArrays(arg, arg);
    }

    auto opers = () @trusted { return ret.val.array.lparray[0 .. 6]; }();
    ret.val.array.rows.shouldEqual(2);
    ret.val.array.columns.shouldEqual(3);
    opers[0].shouldEqualDlang(1.0);
    opers[1].shouldEqualDlang("foo");
    opers[2].shouldEqualDlang(3.0);
    opers[3].shouldEqualDlang(4.0);
    opers[4].shouldEqualDlang(5.0);
    opers[5].shouldEqualDlang(6.0);
}
