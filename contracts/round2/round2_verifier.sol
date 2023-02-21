//
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// 2019 OKIMS
//      ported to solidity 0.6
//      fixed linter warnings
//      added requiere error messages
//
// 2021 Remco Bloemen
//       cleaned up code
//       added InvalidProve() error
//       always revert with InvalidProof() on invalid proof
//       make round2Pairing strict
//
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

library round2Pairing {
  error InvalidProof();

  // The prime q in the base field F_q for G1
  uint256 constant BASE_MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

  // The prime moludus of the scalar field of G1.
  uint256 constant SCALAR_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

  struct G1Point {
    uint256 X;
    uint256 Y;
  }

  // Encoding of field elements is: X[0] * z + X[1]
  struct G2Point {
    uint256[2] X;
    uint256[2] Y;
  }

  /// @return the generator of G1
  function P1() internal pure returns (G1Point memory) {
    return G1Point(1, 2);
  }

  /// @return the generator of G2
  function P2() internal pure returns (G2Point memory) {
    return
      G2Point(
        [
          11559732032986387107991004021392285783925812861821192530917403151452391805634,
          10857046999023057135944570762232829481370756359578518086990519993285655852781
        ],
        [
          4082367875863433681332203403145435568316851327593401208105741076214120093531,
          8495653923123431417604973247489272438418190587263600148770280649306958101930
        ]
      );
  }

  /// @return r the negation of p, i.e. p.addition(p.negate()) should be zero.
  function negate(G1Point memory p) internal pure returns (G1Point memory r) {
    if (p.X == 0 && p.Y == 0) return G1Point(0, 0);
    // Validate input or revert
    if (p.X >= BASE_MODULUS || p.Y >= BASE_MODULUS) revert InvalidProof();
    // We know p.Y > 0 and p.Y < BASE_MODULUS.
    return G1Point(p.X, BASE_MODULUS - p.Y);
  }

  /// @return r the sum of two points of G1
  function addition(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
    // By EIP-196 all input is validated to be less than the BASE_MODULUS and form points
    // on the curve.
    uint256[4] memory input;
    input[0] = p1.X;
    input[1] = p1.Y;
    input[2] = p2.X;
    input[3] = p2.Y;
    bool success;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      success := staticcall(sub(gas(), 2000), 6, input, 0xc0, r, 0x60)
    }
    if (!success) revert InvalidProof();
  }

  /// @return r the product of a point on G1 and a scalar, i.e.
  /// p == p.scalar_mul(1) and p.addition(p) == p.scalar_mul(2) for all points p.
  function scalar_mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
    // By EIP-196 the values p.X and p.Y are verified to less than the BASE_MODULUS and
    // form a valid point on the curve. But the scalar is not verified, so we do that explicitelly.
    if (s >= SCALAR_MODULUS) revert InvalidProof();
    uint256[3] memory input;
    input[0] = p.X;
    input[1] = p.Y;
    input[2] = s;
    bool success;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      success := staticcall(sub(gas(), 2000), 7, input, 0x80, r, 0x60)
    }
    if (!success) revert InvalidProof();
  }

  /// Asserts the pairing check
  /// e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
  /// For example pairing([P1(), P1().negate()], [P2(), P2()]) should succeed
  function pairingCheck(G1Point[] memory p1, G2Point[] memory p2) internal view {
    // By EIP-197 all input is verified to be less than the BASE_MODULUS and form elements in their
    // respective groups of the right order.
    if (p1.length != p2.length) revert InvalidProof();
    uint256 elements = p1.length;
    uint256 inputSize = elements * 6;
    uint256[] memory input = new uint256[](inputSize);
    for (uint256 i = 0; i < elements; i++) {
      input[i * 6 + 0] = p1[i].X;
      input[i * 6 + 1] = p1[i].Y;
      input[i * 6 + 2] = p2[i].X[0];
      input[i * 6 + 3] = p2[i].X[1];
      input[i * 6 + 4] = p2[i].Y[0];
      input[i * 6 + 5] = p2[i].Y[1];
    }
    uint256[1] memory out;
    bool success;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      success := staticcall(sub(gas(), 2000), 8, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
    }
    if (!success || out[0] != 1) revert InvalidProof();
  }
}

contract round2Verifier {
  using round2Pairing for *;

  struct VerifyingKey {
    round2Pairing.G1Point alfa1;
    round2Pairing.G2Point beta2;
    round2Pairing.G2Point gamma2;
    round2Pairing.G2Point delta2;
    round2Pairing.G1Point[] IC;
  }

  struct Proof {
    round2Pairing.G1Point A;
    round2Pairing.G2Point B;
    round2Pairing.G1Point C;
  }

  function verifyingKey() internal pure returns (VerifyingKey memory vk) {
    vk.alfa1 = round2Pairing.G1Point(
      19085465649842209470035951276896972059207207693968749607279417588945544184207,
      2225001544686912464718843116775441565392469917335430201833863722849191485559
    );

    vk.beta2 = round2Pairing.G2Point(
      [10745735959688998095391288873048954979419825813864143867627344220803111073461, 2445872603316623681044244420253955775705588151793702579115395328262564541310],
      [13680561092934922556570980233091319457697962773137258441220395381369281315339, 4830503932761334199428908951571529197332586121936353360622561133090439190930]
    );

    vk.gamma2 = round2Pairing.G2Point(
      [11559732032986387107991004021392285783925812861821192530917403151452391805634, 10857046999023057135944570762232829481370756359578518086990519993285655852781],
      [4082367875863433681332203403145435568316851327593401208105741076214120093531, 8495653923123431417604973247489272438418190587263600148770280649306958101930]
    );

    vk.delta2 = round2Pairing.G2Point(
      [6287928426270773125944083715945454876020250531371311131132137290483781806663, 19435242720831551243236034325336572630929202858010662991662652658675844718261],
      [15709313289570656128023810046921841300413000434248623768275074393683756645279, 19656599985582353143495609887741251905145737112256163002277436207212229836200]
    );

    vk.IC = new round2Pairing.G1Point[](9);

    
      vk.IC[0] = round2Pairing.G1Point(
        15971008697828197827810912720403725740187534926918868485015708903221118150191,
        13004042705649394365247000772070454655065819447350287685568157674952507982602
      );
    
      vk.IC[1] = round2Pairing.G1Point(
        3360938164795162470525591237605497055813807087514469066719452033397056507814,
        4003570333114206450705175434159309423584471929438845123438362877061631987274
      );
    
      vk.IC[2] = round2Pairing.G1Point(
        17617779190267927468183496894815668957412251452188303814311528788802458573060,
        4445475830341568881400837259681460470589941242388981498223382543047734663672
      );
    
      vk.IC[3] = round2Pairing.G1Point(
        412491499760589563748813050362657593755547344230740072605526504055673142247,
        17054044387505464687446128077325098327943475826232458624425201899626860187344
      );
    
      vk.IC[4] = round2Pairing.G1Point(
        12637128800940271754577980783501164564872194619459700560872448890294240178477,
        13630986010221278398170211576855231390743508955189648503059513192798311960993
      );
    
      vk.IC[5] = round2Pairing.G1Point(
        14012993213063673826908839427518533664954765667105931861135969998137439804259,
        21104223326565497504476078262445026609359213481297050328189760627541022918527
      );
    
      vk.IC[6] = round2Pairing.G1Point(
        19159895590642460830955364370713538128029417117171058922784091045778392914137,
        9277469386580635727228178782186747119182796487877688933438693637138432449973
      );
    
      vk.IC[7] = round2Pairing.G1Point(
        6026467622188788735855931551574817543988972812883495157958730395756800729180,
        20048877826593184935836418813607432508437061248944400991717070827964915714328
      );
    
      vk.IC[8] = round2Pairing.G1Point(
        17508289623034750882148463584610939015777782102680354440300034661856545094692,
        7503585299456042146700235157924976825965785170957956082693821462611179926286
      );
    
  }

  /// @dev Verifies a Semaphore proof. Reverts with InvalidProof if the proof is invalid.
  function verifyProof(
    uint[2] memory a,
    uint[2][2] memory b,
    uint[2] memory c,
    uint[8] memory input
  ) public view {
    // If the values are not in the correct range, the round2Pairing contract will revert.
    Proof memory proof;
    proof.A = round2Pairing.G1Point(a[0], a[1]);
    proof.B = round2Pairing.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
    proof.C = round2Pairing.G1Point(c[0], c[1]);

    VerifyingKey memory vk = verifyingKey();

    // Compute the linear combination vk_x of inputs times IC
    if (input.length + 1 != vk.IC.length) revert round2Pairing.InvalidProof();
    round2Pairing.G1Point memory vk_x = vk.IC[0];
    for (uint i = 0; i < input.length; i++) {
      vk_x = round2Pairing.addition(vk_x, round2Pairing.scalar_mul(vk.IC[i+1], input[i]));
    }

    // Check pairing
    round2Pairing.G1Point[] memory p1 = new round2Pairing.G1Point[](4);
    round2Pairing.G2Point[] memory p2 = new round2Pairing.G2Point[](4);
    p1[0] = round2Pairing.negate(proof.A);
    p2[0] = proof.B;
    p1[1] = vk.alfa1;
    p2[1] = vk.beta2;
    p1[2] = vk_x;
    p2[2] = vk.gamma2;
    p1[3] = proof.C;
    p2[3] = vk.delta2;
    round2Pairing.pairingCheck(p1, p2);
  }
}
