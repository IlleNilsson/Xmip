pub trait XmipProtocol {
    fn id(&self) -> &'static str;
    fn name(&self) -> &'static str;
}

pub trait TransportProtocol: XmipProtocol {}

pub trait FrameProtocol<TBase>: XmipProtocol
where
    TBase: TransportProtocol,
{
}

pub trait ContentProtocol<TBase>: XmipProtocol
where
    TBase: XmipProtocol,
{
}
