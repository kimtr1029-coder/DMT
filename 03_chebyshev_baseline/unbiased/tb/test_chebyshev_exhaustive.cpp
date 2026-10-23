#include "../build/chebyshev/chebyshev_sim.cpp"
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

using dut_type = cxxrtl_design::p_per__qam__datapath__chebyshev__q24;

struct record {
    uint32_t snr_q16;
    uint32_t tier;
    uint32_t expected_ber_q24;
};
static_assert(sizeof(record) == 12, "unexpected record packing");

static constexpr std::array<uint32_t, 5> THRESHOLD_DB_Q16 = {
    0u, 6u << 16, 12u << 16, 18u << 16, 24u << 16
};
static constexpr uint32_t HIGH_MARGIN = 100u << 16;

static void set_for_tier(dut_type &dut, const record &row) {
    const uint32_t tier = row.tier;
    dut.p_i__valid.set<bool>(true);
    dut.p_i__snr__linear.set<uint32_t>(row.snr_q16);
    dut.p_i__snr__db.set<uint32_t>(THRESHOLD_DB_Q16[tier]);
    dut.p_i__margin__256.set<uint32_t>(tier == 4 ? 0 : HIGH_MARGIN);
    dut.p_i__margin__64.set<uint32_t>(tier >= 3 ? 0 : HIGH_MARGIN);
    dut.p_i__margin__16.set<uint32_t>(tier >= 2 ? 0 : HIGH_MARGIN);
    dut.p_i__margin__4.set<uint32_t>(0);
}

static void high(dut_type &dut) { dut.p_clk.set<bool>(true); dut.step(); }
static void low(dut_type &dut)  { dut.p_clk.set<bool>(false); dut.step(); }

int main(int argc, char **argv) {
    const std::string path = argc > 1 ? argv[1] : "build/exhaustive_vectors.bin";
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) {
        std::cerr << "cannot open " << path << "\n";
        return 2;
    }
    const auto byte_count = static_cast<size_t>(stream.tellg());
    if (byte_count % sizeof(record)) {
        std::cerr << "bad vector-file length\n";
        return 2;
    }
    std::vector<record> rows(byte_count / sizeof(record));
    stream.seekg(0);
    stream.read(reinterpret_cast<char *>(rows.data()), byte_count);

    dut_type dut;
    dut.p_clk.set<bool>(false);
    dut.p_rst__n.set<bool>(false);
    dut.p_i__valid.set<bool>(false);
    dut.step();
    for (int i = 0; i < 3; ++i) { high(dut); low(dut); }
    dut.p_rst__n.set<bool>(true);
    dut.step();

    size_t output_index = 0;
    int first_output_cycle = -1;
    int previous_output_cycle = -2;
    const size_t final_cycle = rows.size() + 80;
    for (size_t cycle = 0; cycle < final_cycle; ++cycle) {
        if (cycle < rows.size()) set_for_tier(dut, rows[cycle]);
        else dut.p_i__valid.set<bool>(false);
        dut.step();
        high(dut);
        if (dut.p_o__valid.get<bool>()) {
            if (output_index >= rows.size()) {
                std::cerr << "extra output\n";
                return 1;
            }
            const auto actual_ber = dut.p_o__subcarrier__err.get<uint32_t>();
            const auto actual_tier = dut.p_o__m__tier.get<uint32_t>();
            const auto &expected = rows[output_index];
            if (actual_ber != expected.expected_ber_q24 || actual_tier != expected.tier) {
                std::cerr << "mismatch at " << output_index
                          << " BER=" << actual_ber
                          << " expected=" << expected.expected_ber_q24
                          << " tier=" << actual_tier
                          << " expected_tier=" << expected.tier << "\n";
                return 1;
            }
            if (first_output_cycle < 0) first_output_cycle = static_cast<int>(cycle);
            if (output_index && static_cast<int>(cycle) != previous_output_cycle + 1) {
                std::cerr << "throughput bubble\n";
                return 1;
            }
            previous_output_cycle = static_cast<int>(cycle);
            ++output_index;
        }
        low(dut);
    }
    if (output_index != rows.size()) {
        std::cerr << "missing outputs: " << output_index << "/" << rows.size() << "\n";
        return 1;
    }
    std::cout << "PASS: " << output_index
              << " exhaustive Q16-z/QAM RTL vectors; latency="
              << first_output_cycle << " clocks; II=1\n";
    return 0;
}
