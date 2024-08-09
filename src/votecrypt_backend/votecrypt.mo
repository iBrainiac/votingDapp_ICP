// actor {
//   public query func greet(name : Text) : async Text {
//     return "Hello, " # name # "!";
//   };
// };
import Buffer "mo:base/Buffer";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Option "mo:base/Option";

actor MerkleVoting {
    type Voter = {
        voted: Bool;
        encryptedVote: Blob;
    };

    type Candidate = {
        name: Text;
        voteCount: Nat;
    };

    let owner: Principal = Principal.fromActor(this);
    var electionName: Text = "";
    var voters: HashMap<Principal, Voter> = HashMap.HashMap(0, Principal.equal, Principal.hash);
    var candidates: Buffer.Buffer<Candidate> = Buffer.Buffer(0);
    var totalVotes: Nat = 0;
    var electionActive: Bool = false;
    var electionStart: Time.Time = 0;
    var electionDuration: Time.Time = 0;
    var electionEnd: Time.Time = 0;
    var merkleRoot: ?Blob = null;

    public shared(msg) func setMerkleRoot(merkleRoot: Blob) : async () {
        assert(msg.caller == owner);
        self.merkleRoot := ?merkleRoot;
    };

    public shared(msg) func addCandidates(names: [Text]) : async () {
        assert(msg.caller == owner);
        assert(not electionActive, "Election has already started");
        for (name in names.vals()) {
            candidates.add({ name = name; voteCount = 0 });
        };
    };

    public shared(msg) func startElection(duration: Time.Time) : async () {
        assert(msg.caller == owner);
        assert(not electionActive);
        assert(Option.isSome(merkleRoot), "Merkle root is not set");
        assert(candidates.size() > 0, "No candidates added");
        electionActive := true;
        electionStart := Time.now();
        electionDuration := duration;
        electionEnd := electionStart + electionDuration;
    };

    public shared(msg) func vote(merkleProof: [Blob], encryptedVote: Blob) : async () {
        assert(electionActive, "Election is not active");
        assert(Time.now() <= electionEnd, "Election is over");
        assert(not voters.get(msg.caller).unwrap().voted, "You have already voted");
        let merkleLeaf = Blob.fromArray(Hash.hash(Principal.toBlob(msg.caller)));
        assert(verifyMerkleProof(merkleProof, merkleRoot.unwrap(), merkleLeaf), "You are not eligible to vote");

        let voter: Voter = {
            voted = true;
            encryptedVote = encryptedVote;
        };
        voters.put(msg.caller, voter);
        totalVotes += 1;
    };

    public shared(msg) func endElection() : async () {
        assert(Time.now() >= electionEnd, "Election is still ongoing");
        assert(electionActive, "Election has not started");
        electionActive := false;
        electionStart := 0;
        electionDuration := 0;
        electionEnd := 0;
    };

    public query func getNumCandidates() : async Nat {
        candidates.size()
    };

    public query func getCandidate(index: Nat) : async ?Candidate {
        candidates.getOption(index)
    };

    public query func getCandidates() : async [Candidate] {
        Iter.toArray(candidates.vals())
    };

    private func verifyMerkleProof(proof: [Blob], root: Blob, leaf: Blob) : Bool {
        var currentHash = leaf;
        for (entry in proof.vals()) {
            currentHash := if (Hash.equal(currentHash, entry)) {
                Blob.fromArray(Hash.hash(entry ++ currentHash))
            } else {
                Blob.fromArray(Hash.hash(currentHash ++ entry))
            };
        };
        Hash.equal(currentHash, root)
    };
};