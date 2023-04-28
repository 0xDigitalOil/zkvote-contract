pragma circom 2.0.8;
pragma custom_templates;    // TODO : proof of plonk's custom gate

include "../../node_modules/circomlib/circuits/comparators.circom";
include "../../node_modules/circomlib/circuits/poseidon.circom";
include "../nouns/babyjubExtend.circom";

template PoseidonEnc() {
    signal input base[2];
    signal input msg;
    signal input r;

    signal KS[2];
    signal output out;
    signal output kb[2];

    // R = r * G
    component mulG = BabyScaleGenerator();
    mulG.in <== r;
    kb[0] <== mulG.Ax;
    kb[1] <== mulG.Ay;

    // KS = r * C_0
    component mulAny = JubScalarMulAny();
    mulAny.in <== r;
    mulAny.p[0] <== base[0];
    mulAny.p[1] <== base[1];
    KS[0] <== mulAny.out[0];
    KS[1] <== mulAny.out[1];

    // Blinding factor = Poseidon(KS[0])
    component pos = Poseidon(1);
    pos.inputs[0] <== KS[0];
    out <== pos.out + msg;

    // TODO : complete poseidon enc (C.last == S[1]) to protect from "Tampering"

    // TODO(duncan): The simple poseidon may be sufficient.  This proof will
    // guarantee that the sender has encrypted the correct plaintext exactly
    // as described here.
}

// Round2 : f(l)*G == sum(l^k * C[k])
template SumScaleMul(t) {
    signal input f_l;    // f(l)
    signal input l;
    signal input C[t][2];

    // Check f_l < BabyJub scalar field

    signal res[t][2];
    signal output out[2];
    // signal output cmp[2];

    // TODO(duncan): save some constraints by not multiplying on the first loop

    // TODO(duncan): check l < babyjub field, and use Horners scheme, which
    // will avoid needing to care about whether l^k wraps in babyjub vs BN
    // fields.

    var lk;
    lk = 1;// 0^0 = 1
    component mulAny[t];
    component pvkBits[t];
    component babyAdd[t];
    for (var k = 0; k < t; k++) {
        // TODO(duncan): no constraints on lk here?  We need mulAny[k].in to
        // be the **witness element** lk * l, otherwise prover can cheat.

        mulAny[k] = parallel JubScalarMulAny();
        mulAny[k].in <-- lk;     // Do not need Constraints here, just witness
        mulAny[k].p[0] <== C[k][0];
        mulAny[k].p[1] <== C[k][1];

        if (k == 0) {
            res[k][0] <== mulAny[k].out[0];
            res[k][1] <== mulAny[k].out[1];
        } else {
            babyAdd[k] = BabyAdd();
            babyAdd[k].x1 <== mulAny[k].out[0];
            babyAdd[k].y1 <== mulAny[k].out[1];
            babyAdd[k].x2 <== res[k-1][0];
            babyAdd[k].y2 <== res[k-1][1];
            res[k][0] <== babyAdd[k].xout;
            res[k][1] <== babyAdd[k].yout;
        }

        // TODO(duncan): !! contract may need to check that lk^t won't wrap in
        // the native scalar field.

        lk = lk * l;
    }

    out[0] <== res[t-1][0];
    out[1] <== res[t-1][1];

    component scaleMulG = BabyScaleGenerator();
    scaleMulG.in <== f_l;
    scaleMulG.Ax === out[0];
    scaleMulG.Ay === out[1];
}

template Round2(t) {
    signal input f_l;
    signal input l;
    signal input C[t][2];
    signal input CL0[2];

    signal input r;

    signal output out[2]; // f_i_l_commitment
    signal output enc;
    signal output kb[2];

    // Show that f(l) * G = evaluation of committed poly at l
    component S = SumScaleMul(t);
    S.f_l <== f_l;
    S.l <== l;
    for (var i = 0; i < t; i++) {
        S.C[i][0] <== C[i][0];
        S.C[i][1] <== C[i][1];
    }
    f_l_commit[0] <== S.out[0];
    f_l_commit[1] <== S.out[1];

    // Show that ENC(f(l), C_0) = C(iphertext)
    component E = PoseidonEnc();
    E.base[0] <== CL0[0];
    E.base[1] <== CL0[1];
    E.msg <== f_l;
    E.r <== r;
    enc <== E.out;
    kb[0] <== E.kb[0];
    kb[1] <== E.kb[1];
    log("round 2 circuit out[0] ", out[0]);
}

// TODO: enc, out
component main {public [l, C, CL0]} = Round2(2);
