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
      [11648171706324991057439834170375814511941365522755399973226408228150391392110, 3866666640505021386871158083941920929208714118472681533750579093279433000444],
      [13527980239759444217326835116051965511245109669957285090012293769692119275499, 9529114580633668574677573520769192852207127173975004207754419526918325359642]
    );

    vk.IC = new round2Pairing.G1Point[](13);

    
      vk.IC[0] = round2Pairing.G1Point(
        17315715682618995779292076678562708651961686583605614692996459753857988905189,
        13912356145078457322603394994159607581260526734087393647626782314099012743130
      );
    
      vk.IC[1] = round2Pairing.G1Point(
        11642609337095514574211004966862893988557071564995774528594096827098325173595,
        13700358284399173064037246160444199604302694606899013800734467486923774913748
      );
    
      vk.IC[2] = round2Pairing.G1Point(
        18977395160287274538143449380862665947345267515608447881766185599544623218028,
        9010568338476210755983339739544885635792366328667575222370852680071157150204
      );
    
      vk.IC[3] = round2Pairing.G1Point(
        19820340938894413940637266015935503470309197220048736636362110384845772333355,
        3031916164982469562570144976253907105505611867492594979628780595958764817752
      );
    
      vk.IC[4] = round2Pairing.G1Point(
        16773479616418175735338481663704046194282710436076111819026857139204096535909,
        12443551618344435211104300131876930801669595580426428903559221950991856001603
      );
    
      vk.IC[5] = round2Pairing.G1Point(
        19653823543840548866583774580749233370694671240027574371336268232923712040428,
        19011433269899988769121167083204967619790709296599858037637240879257839666947
      );
    
      vk.IC[6] = round2Pairing.G1Point(
        9015633318899814640190598810463981564186191450521195916396909069497630030522,
        14450070358874971598292717339331717077235733422015684222223882007705041684563
      );
    
      vk.IC[7] = round2Pairing.G1Point(
        5642734555847844999745567053714391334254533990896452548913599155724555628197,
        12616744327598618416998204598404778627377214884056839077342393878319169909359
      );
    
      vk.IC[8] = round2Pairing.G1Point(
        666307564110080490649774448901232131830638004547143837729347493793509636707,
        18474270766940670399061621723224321576862240336223477187616140596841819932746
      );
    
      vk.IC[9] = round2Pairing.G1Point(
        165689504225502853339159763160891594310618568019558142312622851921826631726,
        4168898768560621285947733827675604744234877173870687075781835721130891357109
      );
    
      vk.IC[10] = round2Pairing.G1Point(
        20925509248171236888418912663359432573505144888739843631462346946589246287261,
        12726629524563105596513583569769506699718082395798383461826555426365671714401
      );
    
      vk.IC[11] = round2Pairing.G1Point(
        7199236878068415766065475023292805021164248957261375296072210923706598576064,
        16531780910901941603829275548830765028315136047992548258329779395264988076858
      );
    
      vk.IC[12] = round2Pairing.G1Point(
        16464839216565461969094356732663652927280745280820163119084873680590509705510,
        11836364787900593844412709627894265739419649902255773555165118656863244575748
      );
    
  }

  /// @dev Verifies a Semaphore proof. Reverts with InvalidProof if the proof is invalid.
  function verifyProof(
    uint[2] memory a,
    uint[2][2] memory b,
    uint[2] memory c,
    uint[12] memory input
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
