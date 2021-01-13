// get current year
function getCurrentYear() {
    var currentDate = new Date();
    var currentYear = currentDate.getFullYear();
    document.querySelector("#currentDate").innerHTML = currentYear;
}
getCurrentYear();
$(".owl-carousel").owlCarousel({
    autoplay: true,
    loop: true,
    margin: 20,
    autoHeight: true,
    nav: true,
    dots: false,
    autoWidth: false,
    navText: ['<i class="fa fa-angle-left" aria-hidden="true"></i>', '<i class="fa fa-angle-right" aria-hidden="true"></i>'],
    responsive: {
        0: {
            items: 1
        },
        576: {
            autoWidth: true
        }
    }
});