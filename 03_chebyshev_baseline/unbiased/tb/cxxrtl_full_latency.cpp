#include "../build/full/chebyshev_full_sim.cpp"
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>

using dut_type = cxxrtl_design::p_channel__latency__chebyshev__top;
static constexpr size_t N = 255;
static constexpr double Q16 = 65536.0;
static constexpr double Q24 = 16777216.0;
static constexpr double TARGET_BER = 1.0e-4;

static std::array<uint32_t, N> read_hex(const std::string &path) {
    std::array<uint32_t, N> values{};
    std::ifstream stream(path);
    if (!stream) throw std::runtime_error("cannot open " + path);
    std::string line;
    size_t index = 0;
    while (std::getline(stream, line) && index < N) {
        if (line.empty()) continue;
        values[index++] = static_cast<uint32_t>(std::stoul(line, nullptr, 16));
    }
    if (index != N) throw std::runtime_error("wrong profile length in " + path);
    return values;
}

static void low(dut_type &dut)  { dut.p_clk.set<bool>(false); dut.step(); }
static void high(dut_type &dut) { dut.p_clk.set<bool>(true);  dut.step(); }
static void tick(dut_type &dut) { high(dut); low(dut); }

static unsigned bits_from_tier(unsigned tier) {
    static constexpr unsigned bits[] = {0, 2, 4, 6, 8};
    return tier <= 4 ? bits[tier] : 0;
}

static unsigned qam_from_tier(unsigned tier) {
    static constexpr unsigned qam[] = {0, 4, 16, 64, 256};
    return tier <= 4 ? qam[tier] : 0;
}

static double exact_ber(double snr_linear, unsigned qam) {
    if (qam == 0) return 0.0;
    const double scale = (2.0 / std::log2(static_cast<double>(qam))) *
                         (1.0 - 1.0 / std::sqrt(static_cast<double>(qam)));
    const double argument = std::sqrt(3.0 * snr_linear /
                                      (2.0 * (static_cast<double>(qam) - 1.0)));
    return scale * std::erfc(argument);
}

int main(int argc, char **argv) {
    if (argc != 4) {
        std::cerr << "usage: chebyshev_full_latency PROFILE DB_MEM LINEAR_MEM\n";
        return 2;
    }
    const auto db = read_hex(argv[2]);
    const auto linear = read_hex(argv[3]);

    dut_type dut;
    dut.p_clk.set<bool>(false);
    dut.p_rst__n.set<bool>(false);
    dut.p_i__start.set<bool>(false);
    dut.p_i__snr__db.set<uint32_t>(0);
    dut.p_i__snr__linear.set<uint32_t>(0);
    dut.step();
    for (int i = 0; i < 5; ++i) tick(dut);
    dut.p_rst__n.set<bool>(true);
    dut.step();
    for (int i = 0; i < 3; ++i) tick(dut);

    std::array<uint32_t, N> allocation{};
    std::array<bool, N> seen{};
    size_t output_count = 0;
    uint32_t address = 0;
    dut.p_i__start.set<bool>(true);
    high(dut);
    address = dut.p_o__carrier__idx.get<uint32_t>();
    low(dut);
    dut.p_i__start.set<bool>(false);

    int cycles = 0;
    int done_cycle = -1;
    while (cycles < 1000000 && done_cycle < 0) {
        dut.p_i__snr__db.set<uint32_t>(db[address]);
        dut.p_i__snr__linear.set<uint32_t>(linear[address]);
        high(dut);
        ++cycles;
        address = dut.p_o__carrier__idx.get<uint32_t>();
        if (dut.p_o__final__valid.get<bool>()) {
            const auto index = dut.p_o__final__carrier__idx.get<uint32_t>();
            const auto tier = dut.p_o__final__m__tier.get<uint32_t>();
            if (index >= N || tier > 4 || seen[index]) {
                std::cerr << "invalid/duplicate final stream entry\n";
                return 1;
            }
            allocation[index] = tier;
            seen[index] = true;
            ++output_count;
        }
        low(dut);
        if (dut.p_o__done.get<bool>()) done_cycle = cycles;
    }
    if (done_cycle < 0) {
        std::cerr << "timeout\n";
        return 1;
    }
    if (output_count != N) {
        std::cerr << "final stream count=" << output_count << " expected=" << N << "\n";
        return 1;
    }

    uint64_t bits = 0;
    double exact_weighted_error = 0.0;
    std::array<unsigned, 5> tier_counts{};
    for (size_t index = 0; index < N; ++index) {
        const unsigned tier = allocation[index];
        const unsigned loaded_bits = bits_from_tier(tier);
        bits += loaded_bits;
        tier_counts[tier] += 1;
        exact_weighted_error += loaded_bits *
            exact_ber(linear[index] / Q16, qam_from_tier(tier));
    }
    const uint64_t rtl_bits = dut.p_o__total__bits.get<uint32_t>();
    if (rtl_bits != bits) {
        std::cerr << "stream bits=" << bits << " controller bits=" << rtl_bits << "\n";
        return 1;
    }

    const uint64_t weighted_q24 = dut.p_o__weighted__err__q24.get<uint64_t>();
    const double runtime_ber = bits ? weighted_q24 / (Q24 * bits) : 0.0;
    const double offline_exact_ber = bits ? exact_weighted_error / bits : 0.0;
    const double rate_gbps = bits * 20.0 / 552.0;

    std::cout << std::setprecision(12);
    std::cout << "PROFILE=" << argv[1] << "\n";
    // Include the launch edge to match the existing ModelSim convention.
    std::cout << "cycles=" << (done_cycle + 1)
              << " us@100MHz=" << ((done_cycle + 1) / 100.0)
              << " updates=" << dut.p_o__updates.get<uint32_t>()
              << " accepts=" << dut.p_o__refinement__accepts.get<uint32_t>()
              << " scans=" << dut.p_o__refinement__scans.get<uint32_t>()
              << " bits=" << bits << " rate_Gbps=" << rate_gbps << "\n";
    std::cout << "runtime_estimated_BER=" << runtime_ber
              << " offline_exact_BER=" << offline_exact_ber
              << " exact_target_violation=" << (offline_exact_ber > TARGET_BER ? 1 : 0)
              << "\n";
    std::cout << "tiers unused=" << tier_counts[0]
              << " qam4=" << tier_counts[1]
              << " qam16=" << tier_counts[2]
              << " qam64=" << tier_counts[3]
              << " qam256=" << tier_counts[4]
              << " final_stream=" << output_count << "\n";
    return 0;
}
