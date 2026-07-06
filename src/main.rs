use xmip_core::journey_model::ExecutionProfile;
use xmip_core::vertical_slice::{
    apply_assignment, apply_transformation, business_treatment, pass_through_treatment,
    receive_event, RuntimeEvent,
};

fn main() {
    println!("Xmip executable vertical slice");
    println!("Event -> Journey -> Message -> Stream\n");

    let mut work = receive_event(
        RuntimeEvent::FileReceived {
            stream_uri: "store://incoming/order-1001".to_string(),
        },
        business_treatment(),
    );

    println!("Journey created: {}", work.journey.journey_id);
    println!("Message created: {}", work.message.message_id);
    println!("Stream referenced: {}", work.message.stream_ref.uri);
    println!("Execution profile: {:?}\n", work.message.execution_profile);

    let assigned = apply_assignment(&mut work.journey, &work.message);
    println!("Assignment created Message: {}", assigned.message_id);
    println!("Assignment reused Stream: {}\n", assigned.stream_ref.stream_id);

    let transformed = apply_transformation(
        &mut work.journey,
        &assigned,
        "store://transformed/order-1001",
    );
    println!("Transformation created Message: {}", transformed.message_id);
    println!("Transformation created Stream: {}\n", transformed.stream_ref.stream_id);

    let pass_through = receive_event(
        RuntimeEvent::FileReceived {
            stream_uri: "store://incoming/large-transfer".to_string(),
        },
        pass_through_treatment(),
    );

    if pass_through.message.execution_profile == ExecutionProfile::PassThrough {
        println!("Pass-through Journey created: {}", pass_through.journey.journey_id);
        println!("Pass-through Message created: {}", pass_through.message.message_id);
        println!("Pass-through Stream referenced: {}", pass_through.message.stream_ref.uri);
    }
}
