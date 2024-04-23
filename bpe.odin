package bpe

import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

Pair :: struct {
    l, r: string,
}

main :: proc() {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)
    defer {
        for k, v in track.allocation_map {
            fmt.println("Leaked:", v.size, "bytes", "Location:", v.location)
        }
        fmt.eprintfln("=== %v incorrect frees ===", len(track.bad_free_array))
        for bad_free in track.bad_free_array {
            fmt.eprintfln("%v allocation %p was freed badly", bad_free.location, bad_free.memory)
        }
    }        

    big_text := slurp_all()
    defer delete(big_text)

    fmt.printf("length of big text: %d\n", len(big_text))

    lines_of_slices := tokenize_text(big_text)
    defer {
        for line in lines_of_slices {
            delete(line)
        }
        delete(lines_of_slices)
    }

    MAX_ITERATIONS := 2048

    prev_highest_count := 0

    for it := 0; it < MAX_ITERATIONS; it += 1 {
        highest_count_pair, highest_count := get_most_freq_pair(lines_of_slices, prev_highest_count)

        fmt.printf("%d Highest count is %v\n", it, highest_count)
        if highest_count < 2 { break }

        fmt.printf("%d Most frequent pair is %v\n", it, highest_count_pair)

        bmp_merge(&lines_of_slices, highest_count_pair)

        prev_highest_count = highest_count
    }

    ansi_print_lines(lines_of_slices)
}

slurp_all :: proc() -> string {
    out := strings.builder_make() // Allocates
    out_stream := strings.to_stream(&out)

    for i := len(os.args) > 1 ? 1 : 0; i < len(os.args); i += 1 {
        fmt.printf("arg %d: %s\n", i, "stdin" if i == 0 else os.args[i])
        fd: os.Handle = -1
        if i == 0 {
            fd = os.stdin
        } else {
            err : os.Errno
            fd, err = os.open(os.args[i], os.O_RDONLY)
            if err != os.ERROR_NONE {
                fmt.printf("File %s didn't open %v\n", os.args[i], err)
                continue
            }
        }
        defer if i != 0 { os.close(fd) }

        fd_stream := os.stream_from_handle(fd)

        _, err := io.copy(out_stream, fd_stream)
        // TODO: handle err
    }
    return strings.to_string(out)
}
    
tokenize_text :: proc(big_text: string) -> [dynamic][dynamic]string {
    fmt.println("Populating the token arrays...")
    lines_of_slices : [dynamic][dynamic]string

    it := big_text
    for l in strings.split_lines_iterator(&it) {
        // this steps by slices of one utf-8 codepoint
        // since the idea is that we'll be growing them for Byte-Pair Encoding
        s, e := 0, 0    // byte offsets into string
        cp : string     // strings are just slices

        slice_array : [dynamic]string

        for _, ci in l {
            s = e
            e = ci
            cp = l[s:e]
            if cp != "" {
                append(&slice_array, cp)
            }
        }
        s = e
        cp = l[s:]
        if cp != "" {
            append(&slice_array, cp)
        }
        append(&lines_of_slices, slice_array)
    }

    return lines_of_slices
}

get_most_freq_pair :: proc(lines_of_slices: [dynamic][dynamic]string, prev_highest_count: int) -> (Pair, int) {
    fmt.println("Counting pairs...")
    countmap := make(map[Pair]int)
    defer delete(countmap)

    highest_count := 0
    highest_count_pair : Pair

    for line in lines_of_slices {
        for i := 0; i < len(line) - 1; i += 1 {
            pair := Pair{line[i], line[i+1]}
            count := countmap[pair] + 1
            countmap[pair] = count
            if count > highest_count {
                highest_count = count
                highest_count_pair = pair

                // if there's a previous most common pair and our most common pair is
                // equal to or greater than it, then we're done
                if prev_highest_count > 0 && highest_count >= prev_highest_count { break }
            }
        }
    }

    return highest_count_pair, highest_count
}

// do a BPE "merge" by iterating over lines_of_pairs
// and replacing every occurence of pair.1 followed by pair.2
// with a pair starting in the same place but combining the lengths
bmp_merge :: proc(lines_of_slices: ^[dynamic][dynamic]string, highest_count_pair: Pair) {
    for &line in lines_of_slices {
        for i := 0; i < len(line) - 1; i += 1 {
            pair := Pair{line[i], line[i+1]}
            if pair == highest_count_pair {
                line[i] = strings.string_from_ptr(
                    raw_data(line[i]),
                    len(line[i]) + len(line[i+1])
                )
                ordered_remove(&line, i+1)
            }
        }
    }
}

ansi_print_lines :: proc(lines_of_slices: [dynamic][dynamic]string) {
    ansi_base := 30
    ansi_colour := 0
    for line in lines_of_slices {
        for tok in line {
            fmt.printf("\e[%dm%s\e[0m", ansi_base + ansi_colour & 0x07, tok);
            ansi_colour += 1
        }
        fmt.println()
    }
}