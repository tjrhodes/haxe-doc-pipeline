package docpipe;

/**
 * A small CSV reader (RFC 4180): commas between cells, rows on separate lines, and cells in double quotes
 * may hold commas, line breaks and doubled quotes (""). Blank lines are skipped.
 *
 *   Csv.parse('name,age\n"Rossi, Mario",41')   // [["name", "age"], ["Rossi, Mario", "41"]]
 */
class Csv {
    var text:String;
    var pos = 0;
    var rows:Array<Array<String>> = [];
    var row:Array<String> = [];
    var cell = new StringBuf();

    /** Every row of the text, as arrays of cells. Cells are trimmed of surrounding spaces. */
    public static function parse(text:String):Array<Array<String>> {
        var reader = new Csv(text);
        while (reader.pos < text.length) reader.step();
        reader.endRow();
        return reader.rows;
    }

    function new(text:String) {
        this.text = text;
    }

    /** Read one character outside quotes: a comma ends the cell, a line break ends the row, a quote opens a quoted part. */
    function step() {
        var c = text.charAt(pos++);
        switch (c) {
            case ',': endCell();
            case '\n': endRow();
            case '\r': // the \n that follows ends the row
            case '"': quoted();
            default: cell.add(c);
        }
    }

    /** Read a quoted part up to its closing quote; "" inside it is one quote. */
    function quoted() {
        while (pos < text.length) {
            var c = text.charAt(pos++);
            if (c != '"') cell.add(c);
            else if (text.charAt(pos) == '"') cell.add(text.charAt(pos++));
            else return;
        }
    }

    function endCell() {
        row.push(StringTools.trim(cell.toString()));
        cell = new StringBuf();
    }

    /** Finish the row, keeping it unless it was a blank line. */
    function endRow() {
        endCell();
        if (row.length > 1 || row[0] != '') rows.push(row);
        row = [];
    }
}
