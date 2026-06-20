use xmip_linear_kernel::handler_universe::HandlerSpace;
use xmip_linear_kernel::handler_universe_registry::{
    all_handler_repositories, repositories_for_space, validate_handler_universe,
};

fn main() {
    if let Err(error) = validate_handler_universe() {
        eprintln!("Xmip handler universe is invalid: {error}");
        std::process::exit(1);
    }

    let repositories = all_handler_repositories();

    println!("Xmip handler universe");
    println!("=====================");
    println!("Total handler repositories: {}", repositories.len());
    println!();

    for space in ordered_spaces() {
        let space_repositories = repositories_for_space(space);

        println!("{:?}", space);
        println!("{}", "-".repeat(format!("{:?}", space).len()));

        for repository in space_repositories {
            println!(
                "{} -> {}",
                repository.submodule_path, repository.repository_name
            );
        }

        println!();
    }
}

fn ordered_spaces() -> [HandlerSpace; 14] {
    [
        HandlerSpace::FileTransfer,
        HandlerSpace::NetworkWeb,
        HandlerSpace::MessagingStreaming,
        HandlerSpace::Healthcare,
        HandlerSpace::IndustrialIoT,
        HandlerSpace::EnergyUtilities,
        HandlerSpace::FinancePayments,
        HandlerSpace::BusinessDocuments,
        HandlerSpace::DatabaseStorage,
        HandlerSpace::EmailCollaboration,
        HandlerSpace::EnterpriseSaaS,
        HandlerSpace::IdentityDirectory,
        HandlerSpace::GovernmentExchange,
        HandlerSpace::Geospatial,
    ]
}
