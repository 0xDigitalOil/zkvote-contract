const { buildBabyjub } = require('circomlibjs');
const polyval = require( 'compute-polynomial' );
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumberish } from "ethers";
import { ethers } from "hardhat";
import { exit } from "process";
import { Nouns__factory, NvoteVerifier__factory, Round2Verifier__factory } from "../types";
import { generate_zkp_nvote, generate_zkp_round2 } from "./prover";
import { round1 } from "./round1";
import { round2 } from "./round2";

async function jub_test() {
    const jub = await buildBabyjub()
    return jub
}

async function main(
) {
    // init
    const jub = await jub_test()
    const owners = await ethers.getSigners()
    let owner : SignerWithAddress = owners[0]

    // Parameters
    const V = [1, 2, 3]        // voting power per user
    const N_USER = V.length
    const COMMITEE = [owners[0], owners[1], owners[2]]
    const N_COM = COMMITEE.length
    const t = 2

    const r2v = await (new Round2Verifier__factory(owner)).deploy()
    const nvv = await (new NvoteVerifier__factory(owner)).deploy()
    const verifiers = [r2v.address, nvv.address]
    const nc = await (new Nouns__factory(owner)).deploy(
        verifiers,
        COMMITEE.map((e) => e.address),
        COMMITEE.map((e) => e.address),
        V,
        t
        // V.reduce((a,b)=>a+b)
    )

    // 1. Key Generation Round 1 (Committee)
    const {a, C, edwards_twist_C, PK} = await round1(COMMITEE, t, jub, nc)
    console.log("PK : ", PK)
    const edwards_twist_PK = [jub.F.toString(PK[0]), jub.F.toString(PK[1])]

    // 2. Key Generation Round 2 (Committee)
    //const sk = await round2(COMMITEE, a, edwards_twist_C, nc)

    // 3. User Voting
    let o = []
    let r = []
    let R = []
    let R_SUM = jub.Base8
    let M = []
    for (let i = 0; i < N_USER; i++) {
        r.push(Math.floor(Math.random() * 10000)) // TODO: * jub.order)
        R.push(jub.mulPointEscalar(jub.Generator, r[i]))
        R_SUM = jub.addPoint(R_SUM, R[i])

        const m = jub.mulPointEscalar(PK, r[i])
        const vm = jub.addPoint(m, jub.mulPointEscalar(jub.Generator, V[i]))

        if (i % 3 == 0) {
          o.push(0b100)  // yes
          M.push([m, m, vm]);
        } else if (i % 3 == 1) {
          o.push(0b010)  // no
          M.push([m, vm, m]);
        } else {
          o.push(0b001)  // abstain
          M.push([m, m, vm]);
        }
        
        const {proof, publicSignals} = await generate_zkp_nvote(edwards_twist_PK, V[i], r[i], o[i])

        await (await nc.connect(COMMITEE[i]).vote(
          [publicSignals.R[0], publicSignals.R[1]],
          [
            [publicSignals.M[0][0], publicSignals.M[0][1]],
            [publicSignals.M[1][0], publicSignals.M[1][1]],
            [publicSignals.M[2][0], publicSignals.M[2][1]]
          ],
            proof
        )).wait()
        console.log("nvote on-chain verify done!!")
    }
    exit(0)

    // 4. Tally
    const D = []
    for (let i = 0; i < N_COM; i++) {
        D.push(jub.mulPointEscalar(R_SUM, sk[i]))
    }


    // 5. Reveal


    // Performance Profile
}


main()
.then(() => process.exit(0))
.catch(error => {
  console.error(error);
  process.exit(1);
});