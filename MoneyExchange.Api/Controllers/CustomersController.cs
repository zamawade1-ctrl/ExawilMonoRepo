using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MoneyExchange.Api.Models.DTOs.Auth;
using MoneyExchange.Api.Repositories.Interfaces;

namespace MoneyExchange.Api.Controllers;

[Route("api/[controller]")]
public class CustomersController : ApiControllerBase
{
    private readonly ICustomerRepository _repository;

    public CustomersController(ICustomerRepository repository)
    {
        _repository = repository;
    }

    // GET: api/Customers
    [Authorize]
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var response = await _repository.GetAllAsync();
        return HandleResponse(response);
    }

    // GET: api/Customers/5
    [Authorize]
    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetById(int id)
    {
        var response = await _repository.GetByIdAsync(id);
        return HandleResponse(response);
    }

    // POST: api/Customers
    // The registration form: identity + where auto-forwarded USD should go.
    // Anonymous - the customer verifies ownership of the phone number afterwards via OTP.
    [HttpPost]
    public async Task<IActionResult> Register([FromBody] RegisterCustomerDto dto)
    {
        var response = await _repository.RegisterAsync(dto);
        return HandleResponse(response);
    }
}
