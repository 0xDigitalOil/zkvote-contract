pragma circom 2.0.0;

include "./babyjubExtend.circom";

// C = a * G
template JubCommitments(t) {
    signal input a[t];
    signal output C[t][2];

    component pk = BabyScaleGenerator();
    for (var i = 0; i < t; i++) {
        pk.in <== a[i];
        C[i][0] <== pk.Ax;
        C[i][1] <== pk.Ay;
    }
}

// TODO : Posideon Encrypt

// component main {public [C]} = JubCommitments(1);
component main = JubCommitments(1);
