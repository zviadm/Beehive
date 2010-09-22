using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using System.IO;


namespace ConsoleApplication1
{
    class Assemble
    {
        static void Main(string[] args)
        {
            if (args.Length > 1 && args[0].Length > 0 && args[1].Length > 0)
            {
                Assembler assem = new Assembler();
                assem.Assemble(args[0], args[1]);
            }
            else Console.WriteLine("Input or output filename missing");
        }
    }

    public class Assembler
    {
        public void Assemble(string fileName, string outName)
        {
            int lineNumber;
            int errorCnt = 0;
            int pc = 0;
            StreamWriter lst = new StreamWriter("listing.txt");
            String line;
            Hashtable Symbols = new Hashtable();
            ulong[,] Memories = new ulong[3, 1024];
            int[] currentLocations = new int[3];
            int[] locsUsed = new int[3];
            int currentMemory = 0;
            for (int pass = 1; pass < 3; pass++)  //do pass 1, pass 2
            {
                lineNumber = 0;
                for (int j = 0; j < 3; j++)
                { //clear all location counters
                    currentLocations[j] = 0;
                    locsUsed[j] = 0;
                }
                currentMemory = 0; //IM is the target memory.
                StreamReader sr = new StreamReader(fileName);
                while ((line = sr.ReadLine()) != null)
                {
                    lineNumber++;
                    pc = ProcessLine(line, lineNumber, pass, ref Symbols, ref Memories,
                        ref currentLocations, ref currentMemory, ref locsUsed, ref errorCnt, ref lst);
                    if (pass == 2)
                    {
                        if (pc > 0) lst.WriteLine("{0}:\t{1}", pc, line);
                        else lst.WriteLine("     \t{0}", line);
                        //lst.WriteLine("{0}:\t{1}", pc, line);
                    }
                }
                
                sr.Close();
            }
            for (int mx = 0; mx < 3; mx++) lst.WriteLine("Memory {0}: {1} location(s) initialized", mx, locsUsed[mx]);
            lst.WriteLine("{0} Errors.", errorCnt);
            lst.Close();
            for (int mx = 0; mx < 3; mx++)
            {
                Console.WriteLine("Memory {0}: {1} location(s) initialized", mx, locsUsed[mx]);
                if (locsUsed[mx] != 0)
                {
                    for (int i = 0; i < 1024; i++)
                    {
                        ulong x = Memories[mx, i];
                        if (x != 0) //only print nonzero locations
                        {
                            x = x & ~ ((ulong)1 << 63);
                            if (mx == 0) //format printing of IM
                            {  //The instruction layout below is TC-specific.
                                Console.WriteLine(" {0}: Rw = {1}, Ra = {2}, Rb = {3}, F = {4}, Sh = {5}, Sk = {6}, Op = {7}, con = {8}",
                                        i, //location
                                        (x >> 27) & 0x1f, //Rw (5 bits)
                                         (x >> 22)  & 0x1f, //Ra (5 bits)
                                         (x >> 11) & 0x7ff, //Rb (11 bits)
                                        (x >> 8) & 0x7,     //Function (3 bits)
                                        (x >> 6) & 3,       //Shift (2 bits)
                                        (x >> 3) & 7,       //Skip (3 bits
                                        (x & 7),            //Op (3 bits)
                                        (x >> 3) & 0xffffff); //Const (24 bits)
                            }
//                            /*else */ Console.WriteLine(" {0}: {1}", i, x);
                        }
                    }
                }
            }
            //Write the .mem files
            for (int mem = 0; mem < 3; mem++)
            {
                String fname = outName + mem + ".coe";
                ulong contents; //contents of location mem;
                StreamWriter sw = new StreamWriter(fname);
 //               sw.WriteLine("// mem file for memory {0}", mem);
                sw.WriteLine("memory_initialization_radix=16;");
                sw.WriteLine("memory_initialization_vector=");
 //               sw.WriteLine("@0000");
                for (int m = 0; m < 1024; m++)
                {
                    contents = Memories[mem, m] & ~((ulong)1 << 63);
                    sw.Write("{0:X8}", contents);
                    if (m < 1023) sw.WriteLine(",");
                    else sw.WriteLine(";");
                }
                sw.Close();

            }

        }

        public int ProcessLine(String line, int lineNumber, int pass, ref Hashtable Symbols,
            ref ulong[,] Memories, ref int[] currentLocations, ref int currentMemory, ref int[] locsUsed,
            ref int errorCnt, ref StreamWriter lst)
        {
            int pc = 0;
            const int tokmax = 64;
            Token[] tokens = new Token[tokmax];
            for (int i = 0; i < 64; i++) tokens[i] = new Token(0, 0, "");  //we will reuse these
            ulong currentValue;

            if (line.Length > 0)
            {
                int pos = 0; int start = 0; int ntokens = 0; currentValue = 0;
                while (pos < line.Length && ntokens < tokmax) //scan the line for Tokens
                {
                    if (char.IsWhiteSpace(line, pos)) pos++; //skip white space
                    else if (line[pos] == ';') pos = line.Length; //skip the rest of the line
                    else if (char.IsDigit(line, pos)) //get a number
                    {
                        start = pos;
                        while (pos < line.Length && System.Char.IsLetterOrDigit(line[pos]))
                            pos++;  //non-digit or end of line
                        string q = line.Substring(start, pos - start);
                        tokens[ntokens].value = StringValue(q); // long.Parse(q);
                        tokens[ntokens++].type = 0; //a number
                    }
                    else if (System.Char.IsLetter(line[pos]))//get a string
                    {
                        start = pos;
                        while (pos < line.Length && System.Char.IsLetterOrDigit(line[pos])) pos++;
                        tokens[ntokens].str = line.Substring(start, pos - start);
                        tokens[ntokens++].type = 1;  //string
                    }
                    else
                    { //non-letter, non-digit, non-white space.  But stop on ';'.  
                        start = pos;
                        while (pos < line.Length && !System.Char.IsWhiteSpace(line[pos]) &&
                            !System.Char.IsLetter(line[pos]) && (line[pos] != ';')) pos++;
                        tokens[ntokens].str = line.Substring(start, pos - start);
                        tokens[ntokens++].type = 1; //a string
                    }
                }
                //now process each token in a line in turn
                //during pass 1, we define fields, during pass 2, we emit code
                //(any undefined symbols are errors)
                int i = 0;
                while (i < ntokens)
                {
                    Token currentToken = tokens[i];
                    //Check for reserved words
                    if (currentToken.type == 1) // string
                    {
                        if (currentToken.str == ":")
                        { //make a label (pass 1 only)
                            if (pass == 1)
                            {
                                int cloc = currentLocations[currentMemory];
                                if (i == 1)  //may appear only as the second token on a line
                                {
                                    if (tokens[i - 1].type == 1) //must be a string  //this is the key for the Symbol
                                    {
                                        //Make a symbol with value cloc , offset 11.  This is an Rb constant.
                                        //This allows us to write Jump location after labeling "location" 

                                        Symbol s = new Symbol(((ulong)cloc), 11); 
                                        Symbols.Add(tokens[i - 1].str, s);
                                        currentValue |= (ulong)1 << 63;
                                        if (currentMemory == 1) //if we're assembling for RF, we can build the rfrefs automatically
                                        {
                                            Symbol s1 = (Symbol)Symbols["aoff"]; //if null, an exception will be raised shortly
                                            Symbol s2 = (Symbol)Symbols["boff"];
                                            Symbol s3 = (Symbol)Symbols["woff"];
                                            Symbol s1a = new Symbol((ulong)cloc, (int)s1.value);
                                            Symbol s2a = new Symbol((ulong)cloc, (int)s2.value);
                                            Symbol s3a = new Symbol((ulong)cloc, (int)s3.value);
                                            Symbols.Add("a" + (tokens[i - 1].str), s1a);
                                            Symbols.Add("b" + (tokens[i - 1].str), s2a);
                                            Symbols.Add("w" + (tokens[i - 1].str), s3a);
                                        }
                                    }
                                    else
                                    {
                                        lst.WriteLine
                                      ("***Error: Colon may only appear as the second thing on a line. Line {0}\n", lineNumber); errorCnt++;
                                    }
                                }
                                else
                                {
                                    lst.WriteLine
                                  ("***Error: operand of : is not a string. Line {0}\n", lineNumber); errorCnt++;
                                }
                            }
                            currentValue = (ulong)1 << 63; ; //during pass 2, the symbol will have been
                            //looked up and put into currentValue (incorrectly).  Clear it.
                            i++;
                        }
                        else if (currentToken.str == "field")
                        { //define a field (pass 1 only)
                            if (pass == 1)
                            {
                                if ((i + 3) < ntokens) //must have enough operands
                                {
                                    if (tokens[i + 1].type == 1 && tokens[i + 2].type == 0
                                        && tokens[i + 3].type == 0)
                                    {
                                        Symbol s = new Symbol(tokens[i + 2].value, (int)tokens[i + 3].value);
                                        Symbols.Add(tokens[i + 1].str, s);
                                    }
                                    else
                                    {
                                        lst.WriteLine
                                      ("***Error: Arguments for field are of incorrect type. Line{0}", lineNumber); errorCnt++;
                                    }
                                }
                                else
                                {
                                    lst.WriteLine
                                  ("***Error: Too few arguments for field. Line {0}", lineNumber); errorCnt++;
                                }
                            }
                            i = i + 4;
                        }
                        else if (currentToken.str == "rfref")
                        {
                            if (pass == 1) //define three fields (pass 1 only)
                            {
                                if ((i + 2) < ntokens) //must have enough operands
                                {
                                    if (tokens[i + 1].type == 1) //pre-modified register name and the register number.
                                    {
                                        ulong rval = 0;
                                        if (tokens[i + 2].type == 1) //if it's a string, it must resolve to a number
                                        {
                                            Symbol s0 = (Symbol)Symbols[tokens[i + 2].str];
                                            if (s0 != null) rval = s0.value;
                                            else
                                            {
                                                lst.WriteLine("***Error: Undefined sumbol in rfref. Line {0}", lineNumber);
                                                errorCnt++;
                                            }
                                        }

                                        else rval = tokens[i + 2].value;
                                        Symbol s1 = (Symbol)Symbols["aoff"]; //if null, an exception will be raised shortly
                                        Symbol s2 = (Symbol)Symbols["boff"];
                                        Symbol s3 = (Symbol)Symbols["woff"];
                                        Symbol s1a = new Symbol(rval, (int)s1.value);
                                        Symbol s2a = new Symbol(rval, (int)s2.value);
                                        Symbol s3a = new Symbol(rval, (int)s3.value);
                                        Symbols.Add("a" + (tokens[i + 1].str), s1a);
                                        Symbols.Add("b" + (tokens[i + 1].str), s2a);
                                        Symbols.Add("w" + (tokens[i + 1].str), s3a);
                                    }
                                    else
                                    {
                                        lst.WriteLine
                                      ("***Error: Arguments for rfref are of incorrect type. Line{0}", lineNumber); errorCnt++;
                                    }

                                }
                                else
                                {
                                    lst.WriteLine(
                                  "***Error: Too few arguments for rfref. Line {0}", lineNumber); errorCnt++;
                                }
                            }
                            i = i + 3; //skip over arguments
                        }
                        else if (currentToken.str == "mem") //both pass 1 and pass 2
                        {//set the current memory
                            if ((i + 1) < ntokens)
                            {
                                if (tokens[i + 1].type == 0) currentMemory = (int)tokens[i + 1].value; //argument is a number
                                else
                                {
                                    Symbol s = (Symbol)Symbols[tokens[i + 1].str]; //if it's a string, it must resolve to a number.
                                    if (s != null)
                                        currentMemory = (int)s.value;
                                    else
                                    {
                                        lst.WriteLine(
                                      "***Error: Undefined symbol {0}. Line {1}", tokens[i].str, lineNumber); errorCnt++;
                                    }
                                }
                            }
                            else
                            {
                                lst.WriteLine(
                              "***Error: too few arguments. Line{0}", lineNumber); errorCnt++;
                            }
                            i = i + 2; //skip over arguments
                        }
                        else if (currentToken.str == "end") return(pc);
                        else if (currentToken.str == "loc")
                        {//set the current location in the currentMemory
                            if ((i + 1) < ntokens)
                            {
                                if (tokens[i + 1].type == 0)
                                    currentLocations[currentMemory] = (int)tokens[i + 1].value; //argument is a number
                                else
                                {
                                    Symbol s = (Symbol)Symbols[tokens[i + 1]]; //if it's a string, it must resolve to a number.
                                    if (s != null) currentLocations[currentMemory] = (int)s.value;
                                    else
                                    {
                                        lst.WriteLine(
                                      "***Error: Undefined symbol {0}. Line {1}", tokens[i].str, lineNumber); errorCnt++;
                                    }
                                }
                            }
                            else
                            {
                                lst.WriteLine(
                              "***Error: Too few arguments. Line{0}", lineNumber); errorCnt++;
                            }
                            i = i + 2; //skip over arguments
                        }
                        else //look up token, add to currentValue.  If undefined on pass 1, skip.
                        {
                            Symbol s = (Symbol)Symbols[currentToken.str];
                            if (s != null)
                            {
                                ulong v;
                                v = (s.value << s.offset);
                                currentValue |= v;
                                currentValue |= (ulong) 1 << 63; //means location is used
                            }
                            else if (pass == 2)
                            {
                                lst.WriteLine(
                                "***Error. Undefined symbol {0}. Line {1}", tokens[i].str, lineNumber); errorCnt++;
                            }
                            i++;  //skip token
                        }

                    }
                    else //or numbers into currentValue at offset 3.
                    {
                        currentValue = currentValue | (currentToken.value << 3);
                        currentValue |= (ulong) 1 << 63; //mark it used
                        i++;
                    }
                } //while(i < nTokens)
                if (currentValue != 0) //finished all tokens. Store the generated instruction if pass = 2
                {
                    if (pass == 2)
                    {
                        Memories[currentMemory, currentLocations[currentMemory]] = currentValue; //set value
                        locsUsed[currentMemory]++;  //increment the count of used locations
                        if (currentMemory == 0) pc = locsUsed[currentMemory];
                    }
                    currentLocations[currentMemory]++; //increment current location in that memory

                }
            } //if(line.Length > 0)
            return (pc);
        }//ProcessLine

        ulong StringValue(string s)
        {
            int radix = 10;
            ulong value = 0;
            ulong cval;
            for (int i = 0; i < s.Length; i++)
            {
                switch (s[i])
                {
                    case '0': cval = 0; break;
                    case '1': cval = 1; break;
                    case '2': cval = 2; break;
                    case '3': cval = 3; break;
                    case '4': cval = 4; break;
                    case '5': cval = 5; break;
                    case '6': cval = 6; break;
                    case '7': cval = 7; break;
                    case '8': cval = 8; break;
                    case '9': cval = 9; break;
                    case 'a': cval = 10; break;
                    case 'b':
                        if (i == 1)
                        {
                            radix = 2;
                            cval = 0;
                        }
                        else cval = 11; break;
                    case 'c': cval = 12; break;
                    case 'd':
                        if (i == 1) cval = 0;
                        else cval = 13; break;
                    case 'e': cval = 14; break;
                    case 'f': cval = 15; break;
                    case 'x': radix = 16; cval = 0; break;
                    case 'h': radix = 16; cval = 0; break;
                    default: cval = 0; break;
                }
                value = (ulong) radix * value + cval;
            }
            return (value);
        }

    }//Class Assembler

    public class Token  //tokens gathered in line processing
    {
        public int type;
        public ulong value;
        public String str;
        public Token(int type, ulong value, String str)
        {
            this.type = type;
            this.value = value;
            this.str = str;
        }
    }

    public class Symbol  //entries in the symbol table.  a field of two ints.
    {
        public ulong value;
        public int offset;
        public Symbol(ulong value, int offset)
        {
            this.value = value;
            this.offset = offset;
        }
    }

}
