#include <array>
#include <cstdint>
#include <iostream>

struct test_vector {
    uint32_t snr_linear_q16;
    uint32_t snr_db_q16;
    uint32_t margin_256;
    uint32_t margin_64;
    uint32_t margin_16;
    uint32_t margin_4;
    uint32_t expected_ber_q24;
    uint32_t expected_tier;
};

#include VECTOR_HEADER

static void settle(dut_type &dut) { dut.step(); }
static void rising_edge(dut_type &dut) {
    dut.p_clk.set<bool>(true); dut.step();
}
static void falling_edge(dut_type &dut) {
    dut.p_clk.set<bool>(false); dut.step();
}

int main() {
    dut_type dut;
    dut.p_clk.set<bool>(false);
    dut.p_rst__n.set<bool>(false);
    dut.p_i__valid.set<bool>(false);
    dut.p_i__snr__linear.set<uint32_t>(0);
    dut.p_i__snr__db.set<uint32_t>(0);
    dut.p_i__margin__256.set<uint32_t>(0);
    dut.p_i__margin__64.set<uint32_t>(0);
    dut.p_i__margin__16.set<uint32_t>(0);
    dut.p_i__margin__4.set<uint32_t>(0);
    settle(dut);
    for (int i = 0; i < 3; ++i) { rising_edge(dut); falling_edge(dut); }
    dut.p_rst__n.set<bool>(true);
    settle(dut);

    size_t output_index = 0;
    int first_output_cycle = -1;
    int previous_output_cycle = -2;
    bool pass = true;
    const int final_cycle = static_cast<int>(TEST_VECTORS.size()) + 80;
    for (int cycle = 0; cycle < final_cycle; ++cycle) {
        if (cycle < static_cast<int>(TEST_VECTORS.size())) {
            const auto &v = TEST_VECTORS[cycle];
            dut.p_i__valid.set<bool>(true);
            dut.p_i__snr__linear.set<uint32_t>(v.snr_linear_q16);
            dut.p_i__snr__db.set<uint32_t>(v.snr_db_q16);
            dut.p_i__margin__256.set<uint32_t>(v.margin_256);
            dut.p_i__margin__64.set<uint32_t>(v.margin_64);
            dut.p_i__margin__16.set<uint32_t>(v.margin_16);
            dut.p_i__margin__4.set<uint32_t>(v.margin_4);
        } else {
            dut.p_i__valid.set<bool>(false);
        }
        settle(dut);
        rising_edge(dut);
        if (dut.p_o__valid.get<bool>()) {
            if (output_index >= TEST_VECTORS.size()) {
                std::cerr << "extra output at cycle " << cycle << "\n";
                pass = false;
            } else {
                const auto &expected = TEST_VECTORS[output_index];
                uint32_t actual_ber = dut.p_o__subcarrier__err.get<uint32_t>();
                uint32_t actual_tier = dut.p_o__m__tier.get<uint32_t>();
                if (actual_ber != expected.expected_ber_q24 ||
                    actual_tier != expected.expected_tier) {
                    std::cerr << "mismatch " << output_index << ": BER "
                              << actual_ber << " expected " << expected.expected_ber_q24
                              << ", tier " << actual_tier << " expected "
                              << expected.expected_tier << "\n";
                    pass = false;
                }
                if (first_output_cycle < 0) first_output_cycle = cycle;
                if (output_index && cycle != previous_output_cycle + 1) {
                    std::cerr << "throughput bubble\n"; pass = false;
                }
                previous_output_cycle = cycle;
                ++output_index;
            }
        }
        falling_edge(dut);
    }
    if (output_index != TEST_VECTORS.size()) pass = false;
    if (!pass) return 1;
    std::cout << "PASS: " << output_index << " bit-exact vectors; latency="
              << first_output_cycle << " clocks; II=1\n";
    return 0;
}
