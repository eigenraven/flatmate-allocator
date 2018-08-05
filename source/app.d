module app;

import std.stdio, std.algorithm, std.array, std.range, std.conv;
import std.math, std.string, std.format, std.getopt, std.csv, std.random;
import std.container.array, std.file : readText;
import progress;

enum string CMD_USAGE = `%s <flats.csv> <incoming.csv>`;

struct System
{
    string[] flatNames;
    int[] flatCounts;
    string[] mateNames;
    /// preferences of flats
    int[][] flatPreferences;
    /// preferences of mates
    int[][] matePreferences;
}

struct Assignment
{
    // 1-1 assignment of a flat to each member
    int[] matesFlat;

    int[] whosInFlatNo(int flat) const
    {
        return matesFlat.enumerate!int
            .filter!(x => x[1] == flat)
            .map!(x => x[0])
            .array;
    }

    static Assignment makeRandom(in ref System s)
    {
        Assignment a;
        foreach (i, cnt; s.flatCounts)
        {
            a.matesFlat ~= repeat(cast(int) i).take(cnt).array;
        }
        a.matesFlat = randomShuffle(a.matesFlat);
        return a;
    }

    void mutate()
    {
        float prob = 2.0f / matesFlat.length;
        foreach (i; 0 .. matesFlat.length)
        {
            if (uniform01() < prob)
            {
                size_t j = i;
                while (j == i)
                    j = uniform(0, matesFlat.length);
                swapAt(matesFlat, i, j);
            }
        }
    }

    int score(System* sys) const nothrow pure
    {
        int s = 0;
        foreach (mate, flat; matesFlat)
        {
            int fpref = cast(int) sys.flatPreferences[flat].countUntil(mate) + 1;
            int mpref = cast(int) sys.matePreferences[mate].countUntil(flat) + 1;
            if (fpref <= 0)
                fpref = cast(int) sys.flatPreferences[flat].length + 2;
            if (mpref <= 0)
                mpref = cast(int) sys.matePreferences[mate].length + 2;
            s -= mpref + fpref;
        }
        return s;
    }

    void print(System* sys)
    {
        writeln("Assignment score: ", score(sys));
        foreach (fi, fn; sys.flatNames)
        {
            writefln("Flat %s: %(%s, %)", fn, indexed(sys.mateNames, whosInFlatNo(cast(int) fi)));
        }
    }
}

alias Population = Array!Assignment;

System readFiles(string flatsFN, string incomingFN)
{
    string flatsF = readText(flatsFN);
    string incomingF = readText(incomingFN);
    System s;
    // read names
    foreach (record; flatsF.csvReader!string)
    {
        s.flatCounts ~= record.front.to!int;
        record.popFront;
        s.flatNames ~= record.front;
    }
    foreach (record; incomingF.csvReader!string)
    {
        s.mateNames ~= record.front;
    }
    s.flatPreferences = new int[][s.flatNames.length];
    s.matePreferences = new int[][s.mateNames.length];
    // read preferences
    foreach (fi, record; flatsF.csvReader!string
            .enumerate!int)
    {
        record.popFront;
        record.popFront;
        foreach (mate; record)
        {
            if (mate.empty)
                break;
            int pref = cast(int) countUntil(s.mateNames, mate);
            if (pref < 0)
            {
                throw new Exception("Invalid flatmate name: `%s`@%d".format(mate, fi));
            }
            s.flatPreferences[fi] ~= pref;
        }
    }
    foreach (mi, record; incomingF.csvReader!string
            .enumerate!int)
    {
        record.popFront;
        foreach (flat; record)
        {
            if (flat.empty)
                break;
            int pref = cast(int) countUntil(s.flatNames, flat);
            if (pref < 0)
            {
                throw new Exception("Invalid flat name: `%s`@%d".format(flat, mi));
            }
            s.matePreferences[mi] ~= pref;
        }
    }
    //writeln(s.flatPreferences);
    //writeln(s.matePreferences);
    return s;
}

int main(string[] args)
{
    int iterations = 100;
    int population = 300;
    auto gor = getopt(args, "i|iterations", "Number of iterations to calculate", &iterations,
            "p|population", "Number of potential allocations in the state population", &population);
    if (gor.helpWanted || args.length < 3)
    {
        defaultGetoptPrinter(CMD_USAGE.format(args[0]), gor.options);
        return 1;
    }
    System sys = readFiles(args[1], args[2]);
    Population pop;
    pop.length = population * 2;
    Bar bar = new Bar();
    bar.message = () { return "Scrambling and sorting"; };
    bar.max = iterations;
    foreach (ref Assignment a; pop[])
    {
        a = Assignment.makeRandom(sys);
    }
    foreach (i; 0 .. iterations)
    {
        pop[].sort!((a, b) => a.score(&sys) > b.score(&sys));
        // keep worst for reference
        pop[population - 1].matesFlat[] = pop[$ - 1].matesFlat[];
        foreach (j; 0 .. population)
        {
            size_t nj = j + population;
            pop[nj].matesFlat[] = pop[j].matesFlat[];
            pop[nj].mutate;
        }
        bar.next();
    }
    auto spop = pop[].sort!((a, b) => a.score(&sys) > b.score(&sys)).take(population).uniq;
    bar.finish();
    writeln();

    writefln("Top scores: %(%d, %)", spop.take(10).map!(x => x.score(&sys)));
    foreach (i, ref as; spop.take(10).enumerate)
    {
        writefln("Top assignment #%d:", i + 1);
        as.print(&sys);
    }
    return 0;
}
